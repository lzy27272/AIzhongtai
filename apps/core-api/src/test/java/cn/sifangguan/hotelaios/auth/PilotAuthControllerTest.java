package cn.sifangguan.hotelaios.auth;

import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.Mockito.mock;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class PilotAuthControllerTest {
    @Test
    void logoutClearsFederatedBrowserSession() throws Exception {
        MockMvc mvc = MockMvcBuilders.standaloneSetup(
                new PilotAuthController(mock(PilotAuthService.class))).build();

        mvc.perform(post("/api/v1/auth/logout"))
                .andExpect(status().isNoContent())
                .andExpect(header().string("Set-Cookie", containsString(
                        "__Host-hotel_ai_wecom_session=;")))
                .andExpect(header().string("Set-Cookie", containsString("Max-Age=0")))
                .andExpect(header().string("Cache-Control", "no-store, private"));
    }
}
