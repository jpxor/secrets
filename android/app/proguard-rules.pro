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

# Optional JVM-only JGit facilities, not used by Secrets on Android.
# Private clones disable automatic GC and JMX remains disabled. Kerberos is not a supported login mode.
-dontwarn java.lang.ProcessHandle
-dontwarn java.lang.management.ManagementFactory
-dontwarn javax.management.**
-dontwarn org.ietf.jgss.**
