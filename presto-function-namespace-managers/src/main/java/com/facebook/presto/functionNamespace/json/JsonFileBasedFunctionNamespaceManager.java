/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.facebook.presto.functionNamespace.json;

import com.facebook.airlift.log.Logger;
import com.facebook.presto.common.CatalogSchemaName;
import com.facebook.presto.common.QualifiedObjectName;
import com.facebook.presto.common.type.TypeSignature;
import com.facebook.presto.common.type.UserDefinedType;
import com.facebook.presto.functionNamespace.AbstractSqlInvokedFunctionNamespaceManager;
import com.facebook.presto.functionNamespace.ServingCatalog;
import com.facebook.presto.functionNamespace.SqlInvokedFunctionNamespaceManagerConfig;
import com.facebook.presto.functionNamespace.execution.SqlFunctionExecutors;
import com.facebook.presto.spi.PrestoException;
import com.facebook.presto.spi.function.AlterRoutineCharacteristics;
import com.facebook.presto.spi.function.FunctionMetadata;
import com.facebook.presto.spi.function.Parameter;
import com.facebook.presto.spi.function.ScalarFunctionImplementation;
import com.facebook.presto.spi.function.SqlFunctionHandle;
import com.facebook.presto.spi.function.SqlFunctionId;
import com.facebook.presto.spi.function.SqlInvokedFunction;
import com.google.common.collect.ImmutableList;

import javax.inject.Inject;

import java.nio.file.Paths;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

import static com.facebook.presto.common.type.TypeSignature.parseTypeSignature;
import static com.facebook.presto.plugin.base.JsonUtils.parseJson;
import static com.facebook.presto.spi.StandardErrorCode.GENERIC_USER_ERROR;
import static com.facebook.presto.spi.StandardErrorCode.NOT_SUPPORTED;
import static com.facebook.presto.spi.function.FunctionVersion.notVersioned;
import static com.facebook.presto.spi.function.RoutineCharacteristics.Language.CPP;
import static com.google.common.base.Preconditions.checkArgument;
import static com.google.common.base.Preconditions.checkState;
import static com.google.common.collect.ImmutableList.toImmutableList;
import static com.google.common.collect.MoreCollectors.onlyElement;
import static java.lang.Long.parseLong;
import static java.lang.String.format;
import static java.util.Objects.requireNonNull;

public class JsonFileBasedFunctionNamespaceManager
        extends AbstractSqlInvokedFunctionNamespaceManager
{
    private static final Logger log = Logger.get(JsonFileBasedFunctionNamespaceManager.class);

    private final Map<SqlFunctionId, SqlInvokedFunction> latestFunctions = new ConcurrentHashMap<>();
    private final Map<QualifiedObjectName, UserDefinedType> userDefinedTypes = new ConcurrentHashMap<>();
    private final JsonFileBasedFunctionNamespaceManagerConfig managerConfig;

    @Inject
    public JsonFileBasedFunctionNamespaceManager(
            @ServingCatalog String catalogName,
            SqlFunctionExecutors sqlFunctionExecutors,
            SqlInvokedFunctionNamespaceManagerConfig config,
            JsonFileBasedFunctionNamespaceManagerConfig managerConfig)
    {
        super(catalogName, sqlFunctionExecutors, config);
        this.managerConfig = requireNonNull(managerConfig, "managerConfig is null");
        bootstrapNamespaceFromFile();
    }

    private static SqlInvokedFunction copyFunction(SqlInvokedFunction function)
    {
        return new SqlInvokedFunction(
                function.getSignature().getName(),
                function.getParameters(),
                function.getSignature().getReturnType(),
                function.getDescription(),
                function.getRoutineCharacteristics(),
                function.getBody(),
                function.getVersion());
    }

    private void bootstrapNamespaceFromFile()
    {
        try {
            // We can change how to load the function definition file here, to support other formats of input in addition to json if needed.
            JsonBasedUdfFunctionSignatureMap jsonBasedUdfFunctionSignatureMap = parseJson(Paths.get(managerConfig.getFunctionDefinitionFile()), JsonBasedUdfFunctionSignatureMap.class);
            if (jsonBasedUdfFunctionSignatureMap.isEmpty()) {
                return;
            }
            populateNameSpaceManager(jsonBasedUdfFunctionSignatureMap);
        }
        catch (Exception e) {
            log.info("Failed to load function definition for JsonFileBasedFunctionNamespaceManager " + e.getMessage());
        }
    }

    private void populateNameSpaceManager(JsonBasedUdfFunctionSignatureMap jsonBasedUdfFunctionSignatureMap)
    {
        Map<String, List<JsonBasedUdfFunctionMetadata>> udfSignatureMap = jsonBasedUdfFunctionSignatureMap.getUDFSignatureMap();
        udfSignatureMap.forEach((name, metaInfoList) -> {
            List<SqlInvokedFunction> functions = metaInfoList.stream().map(metaInfo -> createSqlInvokedFunction(name, metaInfo)).collect(toImmutableList());
            functions.forEach(function -> createFunction(function, false));
        });
    }

    private SqlInvokedFunction createSqlInvokedFunction(String functionName, JsonBasedUdfFunctionMetadata jsonBasedUdfFunctionMetaData)
    {
        checkState(jsonBasedUdfFunctionMetaData.getRoutineCharacteristics().getLanguage().equals(CPP), "JsonFileBasedInMemoryFunctionNameSpaceManager only supports CPP UDF");
        QualifiedObjectName qualifiedFunctionName = QualifiedObjectName.valueOf(new CatalogSchemaName(getCatalogName(), jsonBasedUdfFunctionMetaData.getSchema()), functionName);
        List<String> parameterNameList = jsonBasedUdfFunctionMetaData.getParamNames();
        List<String> parameterTypeList = jsonBasedUdfFunctionMetaData.getParamTypes();

        ImmutableList.Builder<Parameter> parameterBuilder = ImmutableList.builder();
        for (int i = 0; i < parameterNameList.size(); i++) {
            parameterBuilder.add(new Parameter(parameterNameList.get(i), parseTypeSignature(parameterTypeList.get(i))));
        }

        return new SqlInvokedFunction(
                qualifiedFunctionName,
                parameterBuilder.build(),
                parseTypeSignature(jsonBasedUdfFunctionMetaData.getOutputType()),
                jsonBasedUdfFunctionMetaData.getDocString(),
                jsonBasedUdfFunctionMetaData.getRoutineCharacteristics(),
                "",
                notVersioned());
    }

    @Override
    protected Collection<SqlInvokedFunction> fetchFunctionsDirect(QualifiedObjectName functionName)
    {
        return latestFunctions.values().stream()
                .filter(function -> function.getSignature().getName().equals(functionName))
                .map(JsonFileBasedFunctionNamespaceManager::copyFunction)
                .collect(toImmutableList());
    }

    @Override
    protected UserDefinedType fetchUserDefinedTypeDirect(QualifiedObjectName typeName)
    {
        return userDefinedTypes.get(typeName);
    }

    @Override
    protected FunctionMetadata fetchFunctionMetadataDirect(SqlFunctionHandle functionHandle)
    {
        return fetchFunctionsDirect(functionHandle.getFunctionId().getFunctionName()).stream()
                .filter(function -> function.getRequiredFunctionHandle().equals(functionHandle))
                .map(this::sqlInvokedFunctionToMetadata)
                .collect(onlyElement());
    }

    @Override
    protected ScalarFunctionImplementation fetchFunctionImplementationDirect(SqlFunctionHandle functionHandle)
    {
        return fetchFunctionsDirect(functionHandle.getFunctionId().getFunctionName()).stream()
                .filter(function -> function.getRequiredFunctionHandle().equals(functionHandle))
                .map(this::sqlInvokedFunctionToImplementation)
                .collect(onlyElement());
    }

    @Override
    public void createFunction(SqlInvokedFunction function, boolean replace)
    {
        checkFunctionLanguageSupported(function);
        SqlFunctionId functionId = function.getFunctionId();
        if (!replace && latestFunctions.containsKey(function.getFunctionId())) {
            throw new PrestoException(GENERIC_USER_ERROR, format("Function '%s' already exists", functionId.getId()));
        }

        SqlInvokedFunction replacedFunction = latestFunctions.get(functionId);
        long version = 1;
        if (replacedFunction != null) {
            version = parseLong(replacedFunction.getRequiredVersion()) + 1;
        }
        latestFunctions.put(functionId, function.withVersion(String.valueOf(version)));
    }

    @Override
    public void alterFunction(QualifiedObjectName functionName, Optional<List<TypeSignature>> parameterTypes, AlterRoutineCharacteristics alterRoutineCharacteristics)
    {
        throw new PrestoException(NOT_SUPPORTED, "Drop Function is not supported in JsonFileBasedInMemoryFunctionNameSpaceManager");
    }

    @Override
    public void dropFunction(QualifiedObjectName functionName, Optional<List<TypeSignature>> parameterTypes, boolean exists)
    {
        throw new PrestoException(NOT_SUPPORTED, "Drop Function is not supported in JsonFileBasedInMemoryFunctionNameSpaceManager");
    }

    @Override
    public Collection<SqlInvokedFunction> listFunctions(Optional<String> likePattern, Optional<String> escape)
    {
        return latestFunctions.values();
    }

    @Override
    public void addUserDefinedType(UserDefinedType userDefinedType)
    {
        QualifiedObjectName name = userDefinedType.getUserDefinedTypeName();
        checkArgument(
                !userDefinedTypes.containsKey(name),
                "Parametric type %s already registered",
                name);
        userDefinedTypes.put(name, userDefinedType);
    }
}
