package com.paisatrack.intelligence

import android.content.Context
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig

enum class LlmTask(val wireValue: String) {
    JSON_EXTRACTION("jsonExtraction"),
    ASSISTANT_INTENT("assistantIntent"),
    NARRATIVE("narrative");

    companion object {
        fun fromWire(value: String): LlmTask? = entries.firstOrNull { it.wireValue == value }
    }
}

internal interface LiteRtEngineHandle {
    fun complete(systemInstruction: String, userMessage: String, task: LlmTask): String
    fun close()
}

internal class LiteRtLlmEngine(
    private val context: Context,
    private val spec: LlmModelSpec,
    private val modelPath: () -> String,
) : LiteRtEngineHandle {
    private var engine: Engine? = null

    override fun complete(
        systemInstruction: String,
        userMessage: String,
        task: LlmTask,
    ): String {
        val activeEngine = engine ?: createEngine().also { engine = it }
        val sampler = when (task) {
            LlmTask.JSON_EXTRACTION, LlmTask.ASSISTANT_INTENT ->
                SamplerConfig(topK = 1, topP = 1.0, temperature = 0.0, seed = 1)
            LlmTask.NARRATIVE ->
                SamplerConfig(topK = 20, topP = 0.8, temperature = 0.7, seed = 1)
        }
        val config = ConversationConfig(
            systemInstruction = Contents.of(systemInstruction),
            samplerConfig = sampler,
        )
        return try {
            activeEngine.createConversation(config).use { conversation ->
                val response = conversation.sendMessage("$userMessage\n/no_think")
                response.contents.contents
                    .filterIsInstance<Content.Text>()
                    .joinToString(separator = "") { it.text }
            }
        } catch (error: Throwable) {
            close()
            if (error is OutOfMemoryError) throw error
            throw LlmOperationException("inference_failure")
        }
    }

    override fun close() {
        try {
            engine?.close()
        } catch (_: Exception) {
            // Best effort during lifecycle teardown.
        } finally {
            engine = null
        }
    }

    private fun createEngine(): Engine {
        val created = Engine(
            EngineConfig(
                modelPath = modelPath(),
                backend = Backend.CPU(),
                maxNumTokens = spec.contextTokens,
                cacheDir = context.cacheDir.path,
            ),
        )
        return try {
            created.initialize()
            created
        } catch (error: Throwable) {
            try {
                created.close()
            } catch (_: Exception) {
                // Ignore cleanup failure and report the initialization failure.
            }
            if (error is OutOfMemoryError) throw error
            throw LlmOperationException("initialization_failure")
        }
    }
}
