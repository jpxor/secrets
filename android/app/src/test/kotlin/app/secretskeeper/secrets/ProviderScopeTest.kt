package app.secretskeeper.secrets

import org.junit.Assert.*
import org.junit.Test

class ProviderScopeTest {
    @Test fun releaseAcceptsOnlyConfiguredProvidersAndRejectsLegacyConfigurationsClearly() {
        Providers.requireSupported("Google Drive")
        Providers.requireSupported("SFTP")
        for (type in listOf("OneDrive", "Dropbox", "Git", "FTP", "WebDAV", "")) {
            try {
                Providers.requireSupported(type)
                fail("Unsupported provider was accepted: $type")
            } catch (e: SecretsException) {
                assertTrue(e.message!!.contains("no longer supported"))
                assertTrue(e.message!!.contains("Export your vault"))
            }
        }
    }
}
