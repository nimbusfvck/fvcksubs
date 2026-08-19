# R8 rules for the release build.
#
# Everything here exists because something is reached by *reflection*, which
# R8 cannot see: to it, a class only constructed by name looks unused, so it
# strips or renames it and the lookup fails at runtime with the class right
# there in the APK.

# Room builds its implementation class by name — `WorkDatabase` becomes
# `WorkDatabase_Impl` — and calls its no-arg constructor. Nothing references
# either directly, so R8 removed the constructor and the release build died
# on launch:
#
#   Unable to get provider androidx.startup.InitializationProvider:
#   NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> []
#
# `extends` matches indirect subclasses too, so this covers both the database
# and its generated implementation. It has to keep the class (its *name* is
# what the lookup is built from) as well as the constructor.
#
# Reaches this app through `better_player_plus`, which depends on
# `androidx.work:work-runtime` for its download queue — the crash happens on
# startup regardless of whether anything is ever downloaded, because
# WorkManager initializes itself through androidx.startup.
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# Room resolves these by name from the generated code as well.
-keep @androidx.room.Entity class * { *; }
-dontwarn androidx.room.paging.**
