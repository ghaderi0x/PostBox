/// Static application facts. Keep in sync with pubspec.yaml.
const String appName = 'PostBox';
const String appVersion = '0.2.0';
const String appBuild = '2';
const int settingsSchemaVersion = 1;
const int postboxFormatVersion = 1;

/// Set when the repository is published. Hidden in the UI while empty.
const String repositoryUrl = '';

/// Custom URL scheme used for the OAuth redirect on Android.
const String oauthCustomScheme = 'com.uniqueone.postbox';
const String oauthAndroidRedirect = '$oauthCustomScheme:/oauth2redirect';
