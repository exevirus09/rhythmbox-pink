cp -n data/ui/library-toolbar.ui data/ui/library-toolbar.ui.before-browse-viewall-hide &&
cp -n data/ui/playlist-toolbar.ui data/ui/playlist-toolbar.ui.before-browse-viewall-hide &&
cp -n sources/rb-browser-source.c sources/rb-browser-source.c.before-hide &&
sed -i 's/gtk_widget_show (GTK_WIDGET (source->priv->browser));/gtk_widget_hide (GTK_WIDGET (source->priv->browser));/' sources/rb-browser-source.c &&
perl -0pi -e 's#      <item>\n        <attribute name="label" translatable="yes">Browse</attribute>\n        <attribute name="rb-property-bind">show-browser</attribute>\n        <attribute name="accel">&lt;Primary&gt;b</attribute>\n      </item>\n##g; s#      <item>\n        <attribute name="label" translatable="yes">View All</attribute>\n        <attribute name="rb-signal-bind">reset-filters</attribute>\n      </item>\n##g' data/ui/library-toolbar.ui data/ui/playlist-toolbar.ui
cp -n data/ui/library-toolbar.ui data/ui/library-toolbar.ui.before-browse-hide &&
cp -n data/ui/playlist-toolbar.ui data/ui/playlist-toolbar.ui.before-browse-hide &&
cp -n sources/rb-browser-source.c sources/rb-browser-source.c.before-hide &&
sed -i 's/gtk_widget_show (GTK_WIDGET (source->priv->browser));/gtk_widget_hide (GTK_WIDGET (source->priv->browser));/' sources/rb-browser-source.c &&
perl -0pi -e 's#      <item>\n        <attribute name="label" translatable="yes">Browse</attribute>\n        <attribute name="rb-property-bind">show-browser</attribute>\n        <attribute name="accel">&lt;Primary&gt;b</attribute>\n      </item>\n##' data/ui/library-toolbar.ui data/ui/playlist-toolbar.ui
cp -n data/ui/library-toolbar.ui data/ui/library-toolbar.ui.before-browse-viewall-hide &&
cp -n data/ui/playlist-toolbar.ui data/ui/playlist-toolbar.ui.before-browse-viewall-hide &&
cp -n sources/rb-browser-source.c sources/rb-browser-source.c.before-hide &&
sed -i 's/gtk_widget_show (GTK_WIDGET (source->priv->browser));/gtk_widget_hide (GTK_WIDGET (source->priv->browser));/' sources/rb-browser-source.c &&
perl -0pi -e 's#      <item>\n        <attribute name="label" translatable="yes">Browse</attribute>\n        <attribute name="rb-property-bind">show-browser</attribute>\n        <attribute name="accel">&lt;Primary&gt;b</attribute>\n      </item>\n##g; s#      <item>\n        <attribute name="label" translatable="yes">View All</attribute>\n        <attribute name="rb-signal-bind">reset-filters</attribute>\n      </item>\n##g' data/ui/library-toolbar.ui data/ui/playlist-toolbar.ui
for f in data/ui/library-toolbar.ui data/ui/playlist-toolbar.ui data/ui/podcast-toolbar.ui; do
  cp -n "$f" "$f.before-browse-viewall-hide"
done &&
cp -n sources/rb-browser-source.c sources/rb-browser-source.c.before-hide &&
sed -i 's/gtk_widget_show (GTK_WIDGET (source->priv->browser));/gtk_widget_hide (GTK_WIDGET (source->priv->browser));/' sources/rb-browser-source.c &&
python3 - <<'PY'
from pathlib import Path
import re

for name in ("library-toolbar.ui", "playlist-toolbar.ui", "podcast-toolbar.ui"):
    p = Path("data/ui") / name
    s = p.read_text()
    s = re.sub(r'\s*<item>\s*<attribute name="label"[^>]*>Browse</attribute>.*?</item>', '', s, flags=re.S)
    s = re.sub(r'\s*<item>\s*<attribute name="label"[^>]*>View All</attribute>.*?</item>', '', s, flags=re.S)
    p.write_text(s)
PY
