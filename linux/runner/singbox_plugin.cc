#include "singbox_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <cstring>
#include <string>

static std::string g_stage = "disconnected";

static FlMethodResponse* handle_method_call(FlMethodCall* call) {
  const gchar* method = fl_method_call_get_name(call);

  if (strcmp(method, "prepare") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }
  if (strcmp(method, "start") == 0) {
    g_stage = "error";  // TODO: libbox + TUN when linux/native/libbox is built.
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "stop") == 0) {
    g_stage = "disconnected";
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (strcmp(method, "stage") == 0) {
    g_autoptr(FlValue) result = fl_value_new_string(g_stage.c_str());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }
  if (strcmp(method, "genWgKeys") == 0) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "private", fl_value_new_string(""));
    fl_value_set_string_take(map, "public", fl_value_new_string(""));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  }

  return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call, gpointer) {
  g_autoptr(FlMethodResponse) response = handle_method_call(call);
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("singbox method respond failed: %s", error->message);
  }
}

void register_singbox_plugin(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) method = fl_method_channel_new(
      messenger, "dev.erebrus/singbox", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(method, method_call_cb, nullptr, nullptr);
}