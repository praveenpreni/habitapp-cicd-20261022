package com.example.habittracker;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.http.MediaType;
import com.fasterxml.jackson.databind.ObjectMapper;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
class HabitApiTests {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;

    @Test void validatesName() throws Exception {
        mvc.perform(post("/api/habits").contentType(MediaType.APPLICATION_JSON)
            .content("{\"name\":\"\"}"))
            .andExpect(status().isBadRequest());
    }
    @Test void unknownHabitReturns404() throws Exception {
        mvc.perform(get("/api/habits/999999")).andExpect(status().isNotFound());
    }
    @Test void supportsHabitLifecycle() throws Exception {
        String body = mvc.perform(post("/api/habits").contentType(MediaType.APPLICATION_JSON)
            .content("{\"name\":\"API test\",\"frequency\":\"DAILY\"}"))
            .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        long id = json.readTree(body).get("id").asLong();
        mvc.perform(get("/api/habits/" + id)).andExpect(status().isOk())
            .andExpect(jsonPath("$.name").value("API test"));
        mvc.perform(post("/api/habits/" + id + "/complete"))
            .andExpect(status().isOk()).andExpect(jsonPath("$.currentStreak").value(1));
        mvc.perform(get("/api/habits/" + id + "/stats"))
            .andExpect(status().isOk()).andExpect(jsonPath("$.totalCompletions").value(1));
        mvc.perform(delete("/api/habits/" + id)).andExpect(status().isNoContent());
        mvc.perform(get("/api/habits/" + id)).andExpect(status().isNotFound());
    }
    @Test void livenessWorks() throws Exception {
        mvc.perform(get("/actuator/health/liveness"))
            .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("UP"));
    }
    @Test void readinessWorks() throws Exception {
        mvc.perform(get("/actuator/health/readiness"))
            .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("UP"));
    }
    @Test void dashboardIsServed() throws Exception {
        mvc.perform(get("/")).andExpect(status().isOk());
    }
    @Test void untrustedOriginDoesNotReceiveCorsAccess() throws Exception {
        mvc.perform(get("/api/habits").header("Origin", "https://untrusted.example"))
            .andExpect(header().doesNotExist("Access-Control-Allow-Origin"));
    }
}
