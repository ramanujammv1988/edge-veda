package com.edgeveda.sdk

/** Base exception for Edge Veda SDK errors. */
open class EdgeVedaException(message: String, cause: Throwable? = null) : Exception(message, cause)

class ModelLoadException(message: String) : EdgeVedaException(message)
class InferenceException(message: String) : EdgeVedaException(message)
class MemoryException(message: String) : EdgeVedaException(message)
