# JSch resolves algorithms by configured class name, not direct references.
-keep class app.secretskeeper.secrets.BackupWorker { public <init>(android.content.Context, androidx.work.WorkerParameters); }
# Room instantiates generated databases by reflection during WorkManager startup.
-keep class * extends androidx.room.RoomDatabase { public <init>(); }
-keep class com.jcraft.jsch.DH* { *; }
-keep class com.jcraft.jsch.KeyPair* { *; }
-keep class com.jcraft.jsch.UserAuth* { *; }
-keep class com.jcraft.jsch.jce.** { *; }
-keep class com.jcraft.jsch.bc.** { *; }
-keep class com.jcraft.jsch.jzlib.** { *; }
