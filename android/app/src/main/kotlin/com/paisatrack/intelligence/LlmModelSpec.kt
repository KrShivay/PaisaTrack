package com.paisatrack.intelligence

data class LlmModelSpec(
    val id: String,
    val displayName: String,
    val runtime: String,
    val repository: String,
    val revision: String,
    val fileName: String,
    val downloadUrl: String,
    val sizeBytes: Long,
    val sha256: String,
    val quantization: String,
    val contextTokens: Int,
    val backend: String,
)

object LlmModels {
    /**
     * Revision, byte count, and SHA-256 come from the Hugging Face tree API
     * for this exact commit. The smaller mixed-INT4 artifact is the single
     * production choice; there is no user-facing model picker.
     */
    val active = LlmModelSpec(
        id = "qwen3-0.6b-mixed-int4",
        displayName = "Qwen3 0.6B",
        runtime = "LiteRT-LM 0.14.0",
        repository = "litert-community/Qwen3-0.6B",
        revision = "dd97997951bb15a2a71f539ba17f604707c0b11a",
        fileName = "qwen3_0_6b_mixed_int4.litertlm",
        downloadUrl =
            "https://huggingface.co/litert-community/Qwen3-0.6B/resolve/" +
                "dd97997951bb15a2a71f539ba17f604707c0b11a/" +
                "qwen3_0_6b_mixed_int4.litertlm",
        sizeBytes = 497_664_000L,
        sha256 = "b1baab462f6be49d70eada79d715c2c52cd9ece0cad00bddf6a2c097d23498e9",
        quantization = "mixed INT4",
        contextTokens = 2048,
        backend = "CPU",
    )
}
