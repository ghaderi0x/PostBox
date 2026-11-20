/// Static application facts. Keep in sync with pubspec.yaml.
const String appName = 'PostBox';
const String appVersion = '1.0.0';

/// Optional text shown after the version (for example a release tag).
/// pubspec.yaml cannot carry it, so it lives only here.
const String appVersionSuffix = '';
const String appVersionLabel = '$appVersion$appVersionSuffix';
const String appBuild = '5';
const int settingsSchemaVersion = 2;
const int postboxFormatVersion = 1;

/// Public repository. Releases published here feed the in-app update check.
const String repositoryUrl = 'https://github.com/ghaderi0x/PostBox';
const String repositoryOwner = 'ghaderi0x';
const String repositoryName = 'PostBox';

/// Author credit. Shown only in Settings > About and on the last onboarding
/// page. Do not add it anywhere else.
const String authorName = 'A.M Ghaderi';
const String authorUrl = 'https://github.com/ghaderi0x';

/// Store listings opened by the Android update prompt.
const String androidPackageId = 'com.uniqueone.postbox';
const String myketUrl = 'https://myket.ir/app/$androidPackageId';
const String bazaarUrl = 'https://cafebazaar.ir/app/$androidPackageId';

/// Custom URL scheme used for the OAuth redirect on Android.
const String oauthCustomScheme = 'com.uniqueone.postbox';
const String oauthAndroidRedirect = '$oauthCustomScheme:/oauth2redirect';
