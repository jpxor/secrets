package app.secretskeeper.secrets

import org.junit.Assert.*
import org.junit.Test

class GoogleDriveErrorsTest {
    @Test fun quotaFailureIsNotReportedAsAnAuthorizationFailure() {
        val error = GoogleDriveErrors.http(403, """{"error":{"errors":[{"reason":"storageQuotaExceeded"}]}}""")
        assertTrue(error.contains("storage is full"))
        assertFalse(error.contains("Reconnect"))
        assertTrue(GoogleDriveErrors.http(403, "{}").contains("denied access"))
    }
    @Test fun cancellationConfigurationAndNetworkAreDistinct() {
        assertTrue(GoogleDriveErrors.authorization(null, true).contains("canceled"))
        assertTrue(GoogleDriveErrors.authorization(10).contains("signing fingerprint"))
        assertTrue(GoogleDriveErrors.authorization(7).contains("internet"))
        assertTrue(GoogleDriveErrors.authorization(123).contains("code 123"))
    }
    @Test fun serverMessagesAndUnknownReasonsNeverReachTheUserOrPersistedStatus() {
        val body = """{"error":{"message":"private-provider-data","errors":[{"reason":"private-provider-data"}]}}"""
        assertFalse(GoogleDriveErrors.http(403, body).contains("private-provider-data"))
        assertFalse(GoogleDriveErrors.http(500, "private-provider-data").contains("private-provider-data"))
    }
}
