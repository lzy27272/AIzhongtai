package cn.sifangguan.hotelaios.shared.security;

import jakarta.servlet.http.Cookie;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.oauth2.server.resource.web.BearerTokenResolver;

import static org.assertj.core.api.Assertions.assertThat;

class FederatedCookieBearerTokenResolverTest {
    private final BearerTokenResolver resolver = new SecurityConfiguration()
            .federatedCookieBearerTokenResolver();

    @Test
    void readsWeComSessionFromSecureCookieWhenAuthorizationHeaderIsAbsent() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setCookies(new Cookie(FederatedSessionCookie.NAME, "cookie-jwt"));

        assertThat(resolver.resolve(request)).isEqualTo("cookie-jwt");
    }

    @Test
    void explicitAuthorizationHeaderTakesPrecedenceOverFederatedCookie() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("Authorization", "Bearer header-jwt");
        request.setCookies(new Cookie(FederatedSessionCookie.NAME, "cookie-jwt"));

        assertThat(resolver.resolve(request)).isEqualTo("header-jwt");
    }

    @Test
    void ignoresStaleCookieOnAnonymousExchangeAndLogoutEndpoints() {
        for (String path : new String[] {
                "/api/v1/integrations/wecom/oauth/exchange", "/api/v1/auth/logout"
        }) {
            MockHttpServletRequest request = new MockHttpServletRequest("POST", path);
            request.setCookies(new Cookie(FederatedSessionCookie.NAME, "stale-cookie-jwt"));

            assertThat(resolver.resolve(request)).isNull();
        }
    }
}
