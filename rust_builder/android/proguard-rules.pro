# ONNX Runtime's JNI code looks up these classes by name (for example
# ai.onnxruntime.TensorInfo), so R8 must not remove or rename them.
-keep class ai.onnxruntime.** { *; }
