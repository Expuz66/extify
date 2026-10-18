package com.unicornsonlsd.finamp

import android.app.UiModeManager
import android.content.Intent
import android.content.Intent.CATEGORY_APP_MUSIC
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore.INTENT_ACTION_MUSIC_PLAYER
import android.provider.Settings
import android.system.ErrnoException
import android.system.Os
import android.util.Log
import androidx.annotation.WorkerThread
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import androidx.lifecycle.lifecycleScope
import androidx.mediarouter.app.SystemOutputSwitcherDialogController
import androidx.mediarouter.media.MediaRouter
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext


class MainActivity : AudioServiceActivity() {
    companion object {
        private const val CLIENT_CERT_CHANNEL = "com.unicornsonlsd.finamp/client_certificate"
        private const val CLIENT_CERT_CHANNEL_LOG_TAG = "ClientCertChannel"

        private const val DOWNLOADS_SERVICE_CHANNEL = "com.unicornsonlsd.finamp/downloads_service"
        private const val DOWNLOADS_SERVICE_CHANNEL_LOG_TAG = "DownloadsServiceChannel"

        private const val OUTPUT_SWITCHER_CHANNEL = "com.unicornsonlsd.finamp/output_switcher"
        private const val OUTPUT_SWITCHER_CHANNEL_LOG_TAG = "OutputSwitcherChannel"

        private const val SET_NATIVE_THEME_CHANNEL = "com.unicornsonlsd.finamp/set_native_theme"
        private const val SET_NATIVE_THEME_CHANNEL_LOG_TAG = "setNativeThemeChannel"

        private const val UPDATE_INSTALLER_CHANNEL = "com.unicornsonlsd.finamp/update_installer"
        private const val UPDATE_INSTALLER_CHANNEL_LOG_TAG = "UpdateInstallerChannel"

        private const val UPDATE_DIRECTORY_NAME = "updates"
    }

    private lateinit var mediaRouter: MediaRouter

    override fun onCreate(savedInstanceState: Bundle?) {
        updateIntent(intent)
        super.onCreate(savedInstanceState)

        mediaRouter = MediaRouter.getInstance(this)
    }

    override fun onNewIntent(intent: Intent) {
        updateIntent(intent)
        super.onNewIntent(intent)
    }

    private fun updateIntent(intent: Intent) {
        if (
            (intent.action == INTENT_ACTION_MUSIC_PLAYER || intent.action == CATEGORY_APP_MUSIC) &&
            intent.data == null
        ) {
            intent.data = "finamp://play/surprisemix".toUri()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CLIENT_CERT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installClientCertificate" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val password = call.argument<String>("password")
                    if (bytes == null || password == null) {
                        result.error("INVALID_ARGS", "bytes and password are required", null)
                        return@setMethodCallHandler
                    }
                    lifecycleScope.launch {
                        withContext(Dispatchers.IO) {
                            try {
                                installClientCertificate(bytes, password)

                                Log.i(
                                    CLIENT_CERT_CHANNEL_LOG_TAG,
                                    "Client certificate installed in Android SSL context"
                                )
                                result.success(null)
                            } catch (e: Exception) {
                                Log.e(
                                    CLIENT_CERT_CHANNEL_LOG_TAG,
                                    "Failed to install client certificate",
                                    e
                                )
                                result.error("CERT_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "clearClientCertificate" -> {
                    lifecycleScope.launch {
                        withContext(Dispatchers.IO) {
                            try {
                                clearClientCertificate()

                                Log.i(
                                    CLIENT_CERT_CHANNEL_LOG_TAG,
                                    "Client certificate cleared from Android SSL context"
                                )
                                result.success(null)
                            } catch (e: Exception) {
                                Log.e(CLIENT_CERT_CHANNEL_LOG_TAG, "Failed to clear client certificate", e)
                                result.error("CERT_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> {
                    Log.e(CLIENT_CERT_CHANNEL_LOG_TAG, "Method not found: '${call.method}'")
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOWNLOADS_SERVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "fixDownloadsFileOwner" -> {
                    val downloadLocations = call.argument<List<String>?>("download_locations").orEmpty()
                    lifecycleScope.launch {
                        withContext(Dispatchers.IO) {
                            fixDownloadsFileOwner(downloadLocations)
                        }
                    }
                    result.success(null)
                }
                else -> {
                    Log.e(DOWNLOADS_SERVICE_CHANNEL_LOG_TAG, "Method not found: '${call.method}'")
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SET_NATIVE_THEME_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setNativeThemeMode" -> {
                    val uiManager: UiModeManager =
                        applicationContext.getSystemService(UI_MODE_SERVICE) as UiModeManager

                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                        // Only api >= 31 supports uiManager.setApplicationNightMode
                        // There might be a way to set this on older versions of android, but
                        // I don't feel like debugging that at the moment
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val targetMode = call.argument<Int?>("targetMode")
                    when (targetMode) {
                        0 -> {
                            uiManager.setApplicationNightMode(UiModeManager.MODE_NIGHT_AUTO)
                            result.success(null)
                        }
                        1 -> {
                            uiManager.setApplicationNightMode(UiModeManager.MODE_NIGHT_NO)
                            result.success(null)
                        }
                        2 -> {
                            uiManager.setApplicationNightMode(UiModeManager.MODE_NIGHT_YES)
                            result.success(null)
                        }
                        else -> {
                            Log.e(SET_NATIVE_THEME_CHANNEL_LOG_TAG, "Method not found: '${call.method}'")
                            result.notImplemented()
                        }
                    }
                }
                else -> {
                    Log.e(SET_NATIVE_THEME_CHANNEL_LOG_TAG, "Method not found: '${call.method}'")
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OUTPUT_SWITCHER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            Log.d(OUTPUT_SWITCHER_CHANNEL_LOG_TAG, "Calling method: '${call.method}'")
            when (call.method) {
                "showOutputSwitcherDialog" -> {
                    showOutputSwitcherDialog()
                    result.success(null)
                }
                "getRoutes" -> {
                    val routes = mediaRouter.routes
                    routes.log()
                    result.success(routes.map { route ->
                        mapOf(
                            "name" to route.name,
                            "connectionState" to route.connectionState,
                            "isSystemRoute" to route.isSystemRoute,
                            "isDefault" to route.isDefault,
                            "isDeviceSpeaker" to route.isDeviceSpeaker,
                            "isBluetooth" to route.isBluetooth,
                            "volume" to route.volume,
                            "providerPackageName" to route.provider.packageName,
                            "isSelected" to route.isSelected,
                            "deviceType" to route.deviceType,
                            "description" to route.description,
                            "extras" to route.extras,
                            "iconUri" to route.iconUri,
                            // "controlFilters" to route.controlFilters,
                        )
                    })
                }
                "setOutputToDeviceSpeaker" -> {
                    val routes = mediaRouter.routes
                    routes.log()
                    val deviceSpeakerRoute = routes.first { route -> route.isDeviceSpeaker }
                    mediaRouter.selectRoute(deviceSpeakerRoute)
                    result.success(null)
                }
                "setOutputToBluetoothDevice" -> {
                    val routes = mediaRouter.routes
                    routes.log()
                    val bluetoothRoute = routes.first { route -> route.isBluetooth }
                    mediaRouter.selectRoute(bluetoothRoute)
                    result.success(null)
                }
                "setOutputToRouteByName" -> {
                    val routes = mediaRouter.routes
                    routes.log()
                    val targetRoute = routes.first { route ->
                        route.name == call.argument<String>("name")
                    }
                    mediaRouter.selectRoute(targetRoute)
                    result.success(null)
                }
                "openBluetoothSettings" -> {
                    startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(null)
                }
                else -> {
                    Log.e(OUTPUT_SWITCHER_CHANNEL_LOG_TAG, "Method not found: '${call.method}'")
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_INSTALLER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSupportedAbis" -> {
                    result.success(Build.SUPPORTED_ABIS.toList())
                }
                "getUpdateDir" -> {
                    try {
                        result.success(updateDirectory().absolutePath)
                    } catch (e: Exception) {
                        Log.e(UPDATE_INSTALLER_CHANNEL_LOG_TAG, "Could not prepare the update directory", e)
                        result.error("UPDATE_DIR_ERROR", e.message, null)
                    }
                }
                "getInstalledAppInfo" -> {
                    try {
                        result.success(installedAppInfo())
                    } catch (e: Exception) {
                        Log.e(UPDATE_INSTALLER_CHANNEL_LOG_TAG, "Could not read the installed app info", e)
                        result.error("INSTALLED_APP_ERROR", e.message, null)
                    }
                }
                "inspectApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGS", "path is required", null)
                        return@setMethodCallHandler
                    }
                    // Hashing a ~50 MB APK must stay off the UI thread.
                    lifecycleScope.launch {
                        withContext(Dispatchers.IO) {
                            try {
                                result.success(inspectApk(File(path)))
                            } catch (e: Exception) {
                                Log.e(UPDATE_INSTALLER_CHANNEL_LOG_TAG, "Could not inspect the downloaded APK", e)
                                result.error("APK_INSPECTION_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGS", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApk(File(path))
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(UPDATE_INSTALLER_CHANNEL_LOG_TAG, "Could not open the package installer", e)
                        result.error("APK_INSTALL_ERROR", e.message, null)
                    }
                }
                else -> {
                    Log.e(UPDATE_INSTALLER_CHANNEL_LOG_TAG, "Method not found: '${call.method}'")
                    result.notImplemented()
                }
            }
        }
    }

    private fun installClientCertificate(bytes: ByteArray, password: String) {
        val keyStore = KeyStore.getInstance("PKCS12")
        keyStore.load(ByteArrayInputStream(bytes), password.toCharArray())

        val keyManagerFactory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        keyManagerFactory.init(keyStore, password.toCharArray())

        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(keyManagerFactory.keyManagers, null, null)

        SSLContext.setDefault(sslContext)
        HttpsURLConnection.setDefaultSSLSocketFactory(sslContext.socketFactory)
    }

    private fun clearClientCertificate() {
        val defaultContext = SSLContext.getInstance("TLS")
        defaultContext.init(null, null, null)
        SSLContext.setDefault(defaultContext)
        HttpsURLConnection.setDefaultSSLSocketFactory(defaultContext.socketFactory)
    }

    /**
     * Fixes the owner of downloaded files.
     *
     * Originally, files downloaded by the app were set to a special "cache" user group,
     * which caused the system to count all downloads as cache files.
     * Manually setting the group to the app's UID (which is equal to the gid) fixes this behavior for past downloads.
     */
    @WorkerThread
    private fun fixDownloadsFileOwner(downloadLocations: List<String>) {
        val appUid = applicationInfo.uid
        val cacheGid = try {
            Os.stat(context.cacheDir.absolutePath).st_gid
        } catch (e: ErrnoException) {
            Log.e(DOWNLOADS_SERVICE_CHANNEL_LOG_TAG, "Failed to get cache directory GID", e)
            return
        }
        for (downloadLocation in downloadLocations) {
            val downloadDirectory = File(downloadLocation)
            if (!downloadDirectory.isDirectory) {
                Log.w(DOWNLOADS_SERVICE_CHANNEL_LOG_TAG, "Download location is not a directory: $downloadLocation")
                continue
            }

            for (file in downloadDirectory.walkTopDown()) {
                try {
                    if (!file.isFile) continue

                    // Skip files not owned by the cache group
                    val gid = Os.stat(file.absolutePath).st_gid
                    if (gid != cacheGid) continue

                    Os.chown(file.absolutePath, -1, appUid) // uid -1 keeps current owner
                } catch (e: ErrnoException) {
                    Log.e(DOWNLOADS_SERVICE_CHANNEL_LOG_TAG, "Failed to fix owner for: ${file.absolutePath}", e)
                }
            }
        }
    }

    private fun List<MediaRouter.RouteInfo>.log() {
        forEach { route ->
            Log.d(
                OUTPUT_SWITCHER_CHANNEL_LOG_TAG,
                "Route: ${route.name}, connection state: ${route.connectionState}, system route: ${route.isSystemRoute}, default: ${route.isDefault}, device speaker: ${route.isDeviceSpeaker}, bluetooth: ${route.isBluetooth}, volume: ${route.volume}, provider: ${route.provider.packageName}"
            )
        }
    }

    private fun showOutputSwitcherDialog() {
        SystemOutputSwitcherDialogController.showDialog(this)
    }

    /** App-private folder the FileProvider exposes to the package installer. */
    private fun updateDirectory(): File {
        val directory = File(filesDir, UPDATE_DIRECTORY_NAME)
        if (!directory.exists()) {
            directory.mkdirs()
        }
        return directory
    }

    private fun installedAppInfo(): Map<String, Any?> {
        val info = packageManager.getPackageInfo(packageName, signingFlags())
        return mapOf(
            "packageName" to packageName,
            "versionName" to (info.versionName ?: ""),
            "versionCode" to versionCodeOf(info),
            "signingSha256" to signingDigests(info).firstOrNull().orEmpty(),
            "signingSha256All" to signingDigests(info),
        )
    }

    /** Reads package identity, signature and checksum straight from the APK. */
    @WorkerThread
    private fun inspectApk(file: File): Map<String, Any?> {
        if (!file.isFile) {
            throw IllegalArgumentException("The downloaded file does not exist.")
        }
        val info = packageManager.getPackageArchiveInfo(file.absolutePath, signingFlags())
            ?: throw IllegalArgumentException("Android could not read the downloaded file as an APK.")
        return mapOf(
            "packageName" to (info.packageName ?: ""),
            "versionName" to (info.versionName ?: ""),
            "versionCode" to versionCodeOf(info),
            "signingSha256" to signingDigests(info).firstOrNull().orEmpty(),
            "signingSha256All" to signingDigests(info),
            "fileSha256" to sha256HexOfFile(file),
            "bytes" to file.length(),
        )
    }

    /**
     * Hands [file] to Android's package installer.
     *
     * This only *opens* the installer: the system shows the update prompt and
     * the user confirms. The app never installs anything on its own.
     */
    private fun installApk(file: File) {
        if (!file.isFile) {
            throw IllegalArgumentException("The downloaded update no longer exists.")
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.update_installer", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        Log.i(UPDATE_INSTALLER_CHANNEL_LOG_TAG, "Opened the package installer for ${file.name}")
    }

    private fun signingFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }

    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

    /**
     * Every signing certificate digest Android knows about for this package, so
     * a key rotation history still matches.
     */
    private fun signingDigests(info: PackageInfo): List<String> {
        val digests = LinkedHashSet<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo
            if (signingInfo != null) {
                signingInfo.apkContentsSigners?.forEach { digests.add(sha256Hex(it.toByteArray())) }
                signingInfo.signingCertificateHistory?.forEach { digests.add(sha256Hex(it.toByteArray())) }
            }
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.forEach { digests.add(sha256Hex(it.toByteArray())) }
        }
        return digests.toList()
    }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    @WorkerThread
    private fun sha256HexOfFile(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val read = stream.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
