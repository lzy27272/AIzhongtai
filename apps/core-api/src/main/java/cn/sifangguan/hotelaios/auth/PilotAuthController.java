package cn.sifangguan.hotelaios.auth;

import cn.sifangguan.hotelaios.shared.security.FederatedSessionCookie;
import jakarta.validation.Valid;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;

@RestController
@RequestMapping("/api/v1/auth")
@ConditionalOnProperty(name = "app.security.local-login.enabled", havingValue = "true")
public class PilotAuthController {
    private final PilotAuthService service;

    public PilotAuthController(PilotAuthService service) {
        this.service = service;
    }

    @PostMapping("/login")
    public PilotAuthModels.LoginResponse login(@Valid @RequestBody PilotAuthModels.LoginRequest request) {
        return service.login(request);
    }

    @PostMapping("/password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void changePassword(@Valid @RequestBody PilotAuthModels.ChangePasswordRequest request) {
        service.changePassword(request);
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout() {
        return ResponseEntity.noContent()
                .header(HttpHeaders.SET_COOKIE, FederatedSessionCookie.clear().toString())
                .header(HttpHeaders.CACHE_CONTROL, "no-store, private")
                .build();
    }
}
