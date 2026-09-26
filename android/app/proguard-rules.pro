# Please add these rules to your existing keep rules in order to suppress warnings.
# This is generated automatically by the Android Gradle plugin.
-dontwarn com.google.protobuf.Internal$ProtoMethodMayReturnNull
-dontwarn com.google.protobuf.Internal$ProtoNonnullApi
-dontwarn com.google.protobuf.ProtoPresenceBits

# WorkManager's initializer reflectively constructs this Room-generated class.
# R8 otherwise removes its no-argument constructor and the app crashes before
# MainActivity starts.
-keep class androidx.work.impl.WorkDatabase_Impl {
    public <init>();
}
