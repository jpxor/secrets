package app.secretskeeper.secrets

/** Only application-authored messages may cross into UI or persistent diagnostics. */
class SecretsException(message: String) : IllegalStateException(message)
inline fun ensure(condition: Boolean, message: () -> String = { "Invalid backup request." }) {
    if (!condition) throw SecretsException(message())
}
fun fail(message: String): Nothing = throw SecretsException(message)
