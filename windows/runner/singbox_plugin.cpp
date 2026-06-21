#include "singbox_plugin.h"

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

namespace {

std::string g_stage = "disconnected";

class SingboxMethodHandler {
 public:
  static void Handle(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "prepare") {
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (call.method_name() == "start") {
      g_stage = "connecting";
      // TODO: start libbox (windows/native/libbox) with Wintun when built.
      g_stage = "error";
      result->Success();
      return;
    }
    if (call.method_name() == "stop") {
      g_stage = "disconnected";
      result->Success();
      return;
    }
    if (call.method_name() == "stage") {
      result->Success(flutter::EncodableValue(g_stage));
      return;
    }
    if (call.method_name() == "genWgKeys") {
      // Placeholder keys until libbox keygen is wired.
      flutter::EncodableMap keys;
      keys[flutter::EncodableValue("private")] = flutter::EncodableValue("");
      keys[flutter::EncodableValue("public")] = flutter::EncodableValue("");
      result->Success(flutter::EncodableValue(keys));
      return;
    }
    result->NotImplemented();
  }
};

}  // namespace

void RegisterSingboxPlugin(flutter::FlutterViewController* controller) {
  auto* messenger = controller->engine()->messenger();

  auto method = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "dev.erebrus/singbox",
      &flutter::StandardMethodCodec::GetInstance());
  method->SetMethodCallHandler(
      [](const auto& call, auto result) {
        SingboxMethodHandler::Handle(call, std::move(result));
      });

  auto status = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      messenger, "dev.erebrus/singbox/status",
      &flutter::StandardMethodCodec::GetInstance());
  status->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [](const flutter::EncodableValue*,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            events->Success(flutter::EncodableValue(g_stage));
            return nullptr;
          },
          [](const flutter::EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            return nullptr;
          }));

  auto stats = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      messenger, "dev.erebrus/singbox/stats",
      &flutter::StandardMethodCodec::GetInstance());
  stats->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [](const flutter::EncodableValue*,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            flutter::EncodableMap m;
            m[flutter::EncodableValue("rx_bytes")] = flutter::EncodableValue(0);
            m[flutter::EncodableValue("tx_bytes")] = flutter::EncodableValue(0);
            m[flutter::EncodableValue("downlink_bps")] = flutter::EncodableValue(0);
            m[flutter::EncodableValue("uplink_bps")] = flutter::EncodableValue(0);
            events->Success(flutter::EncodableValue(m));
            return nullptr;
          },
          [](const flutter::EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            return nullptr;
          }));
}