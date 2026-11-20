@tool
extends EditorPlugin
var exporter: EditorExportPlugin
func _enter_tree() -> void:
	exporter=IdentityExport.new()
	add_export_plugin(exporter)
func _exit_tree() -> void:
	remove_export_plugin(exporter)
	exporter=null
class IdentityExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "SestriaGoogleIdentity"
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid
	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["androidx.credentials:credentials:1.5.0","androidx.credentials:credentials-play-services-auth:1.5.0","com.google.android.libraries.identity.googleid:googleid:1.2.1"])
	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return '<meta-data android:name="org.godotengine.plugin.v2.SestriaGoogle" android:value="com.sestria.platform.SestriaGoogle" /><meta-data android:name="org.godotengine.plugin.v2.SestriaLAN" android:value="com.sestria.platform.SestriaLAN" /><meta-data android:name="org.godotengine.plugin.v2.SestriaUpdates" android:value="com.sestria.platform.SestriaUpdates" /><provider android:name="com.sestria.platform.SestriaUpdateProvider" android:authorities="${applicationId}.sestria.updates" android:exported="false" android:grantUriPermissions="true"><meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/sestria_update_paths" /></provider>'
	func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />'
