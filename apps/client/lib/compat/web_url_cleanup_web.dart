import "dart:html" as html;

import "package:flutter/foundation.dart";

/// Con estrategia por path (`/login`) OAuth puede dejar también `#/login`.
void normalizeWebPathAndFragmentImpl() {
  if (!kIsWeb) return;
  try {
    final u = Uri.parse(html.window.location.href);
    if (!u.hasFragment) return;
    final frag = u.fragment;
    if (frag.isEmpty) return;
    final fragPath = frag.startsWith("/") ? frag : "/$frag";
    var path = u.path.isEmpty ? "/" : u.path;
    if (path.length > 1 && path.endsWith("/")) {
      path = path.substring(0, path.length - 1);
    }
    if (fragPath == path) {
      html.window.history.replaceState(null, "", u.replace(fragment: "").toString());
    }
  } catch (_) {
    /* no bloquear arranque */
  }
}
