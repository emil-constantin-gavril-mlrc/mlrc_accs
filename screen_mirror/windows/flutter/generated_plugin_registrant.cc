//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <bonsoir_windows/bonsoir_windows_plugin_c_api.h>
#include <desktop_screenshot/desktop_screenshot_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  BonsoirWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("BonsoirWindowsPluginCApi"));
  DesktopScreenshotPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DesktopScreenshotPluginCApi"));
}
