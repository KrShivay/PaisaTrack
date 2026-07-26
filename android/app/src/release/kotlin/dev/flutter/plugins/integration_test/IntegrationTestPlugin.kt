package dev.flutter.plugins.integration_test

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Workaround for Flutter 3.44.4 generating a release registrant entry for the
 * dev-only integration_test plugin while omitting that plugin from the release
 * classpath. Remove this release-only no-op after the Flutter tool generates a
 * variant-correct registrant.
 */
class IntegrationTestPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit
}
