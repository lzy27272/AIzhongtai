package cn.sifangguan.hotelaios.shared.security;

import org.springframework.http.ResponseCookie;

import java.time.Duration;
import java.time.OffsetDateTime;

/** Browser session transport used only after a successful federated identity exchange. */
public final class FederatedSessionCookie {
    public static final String NAME = "__Host-hotel_ai_wecom_session";

    private FederatedSessionCookie() { }

    public static ResponseCookie create(String accessToken, OffsetDateTime expiresAt) {
        long maxAgeSeconds = Math.max(1, Duration.between(OffsetDateTime.now(), expiresAt).toSeconds());
        return ResponseCookie.from(NAME, accessToken)
                .httpOnly(true)
                .secure(true)
                .sameSite("Lax")
                .path("/")
                .maxAge(maxAgeSeconds)
                .build();
    }

    public static ResponseCookie clear() {
        return ResponseCookie.from(NAME, "")
                .httpOnly(true)
                .secure(true)
                .sameSite("Lax")
                .path("/")
                .maxAge(0)
                .build();
    }
}
