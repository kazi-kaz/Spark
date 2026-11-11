The Spark app icon in ../Iridium/Assets.xcassets/AppIcon.appiconset/AppIcon.png
is an amber lightning bolt on a dark graphite tile. It is drawn by
make_spark_icon.py (needs Pillow) and is an opaque 1024 × 1024 RGB PNG:

    python3 make_spark_icon.py ../Iridium/Assets.xcassets/AppIcon.appiconset/AppIcon.png

The bolt outline matches SparkBolt in ../Iridium/Views/SparkTheme.swift; change
both together. The script was written with AI assistance.

AppIcon-source.png is the 10 × 10 source of the previous Iridium icon, kept for
reference. It is no longer used by the build.
