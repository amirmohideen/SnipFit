# MediaPipe Tasks (tap-to-select) uses reflection and JNI.
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
# LiteRT / TensorFlow Lite (face_detection_tflite).
-keep class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**
-keep class com.google.ai.edge.litert.** { *; }
-dontwarn com.google.ai.edge.litert.**
