const {
  withProjectBuildGradle,
  withAppBuildGradle,
  withDangerousMod,
  AndroidConfig,
} = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

/**
 * Expo Config Plugin for Edge Veda
 * Automatically configures the native module during expo prebuild
 */

/**
 * Add New Architecture flag to gradle.properties if not present
 */
function withNewArchitectureGradleProperties(config) {
  return withDangerousMod(config, [
    'android',
    async (config) => {
      const gradlePropertiesPath = path.join(
        config.modRequest.platformProjectRoot,
        'gradle.properties'
      );

      if (fs.existsSync(gradlePropertiesPath)) {
        let contents = fs.readFileSync(gradlePropertiesPath, 'utf-8');
        
        // Only add if not already present
        if (!contents.includes('newArchEnabled')) {
          contents += '\n# Enable New Architecture (optional - defaults to false)\n';
          contents += '# Uncomment to enable React Native New Architecture\n';
          contents += '# newArchEnabled=true\n';
          
          fs.writeFileSync(gradlePropertiesPath, contents);
        }
      }

      return config;
    },
  ]);
}

/**
 * Ensure minimum SDK versions for Edge Veda
 */
function withMinSdkVersion(config) {
  return withAppBuildGradle(config, (config) => {
    if (config.modResults.contents) {
      // Ensure minSdkVersion is at least 21
      config.modResults.contents = config.modResults.contents.replace(
        /minSdkVersion\s*=?\s*\d+/,
        'minSdkVersion 21'
      );
    }
    return config;
  });
}

/**
 * Add Edge Veda specific build configuration
 */
function withEdgeVedaBuildConfig(config) {
  return withProjectBuildGradle(config, (config) => {
    // Ensure Kotlin is available
    if (config.modResults.contents) {
      const kotlinVersion = '1.8.0';
      
      if (!config.modResults.contents.includes('kotlin-gradle-plugin')) {
        // Add Kotlin plugin to buildscript dependencies
        config.modResults.contents = config.modResults.contents.replace(
          /dependencies\s*{/,
          `dependencies {
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:${kotlinVersion}"`
        );
      }
    }
    return config;
  });
}

/**
 * Main plugin function
 */
const withEdgeVeda = (config, props = {}) => {
  config = withMinSdkVersion(config);
  config = withNewArchitectureGradleProperties(config);
  config = withEdgeVedaBuildConfig(config);

  return config;
};

module.exports = withEdgeVeda;