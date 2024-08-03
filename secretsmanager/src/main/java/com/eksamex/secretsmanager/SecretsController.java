package com.eksamex.secretsmanager;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

@RestController
public class SecretsController {

    private final SecretsManagerService secretsManagerService;

    @Autowired
    public SecretsController(SecretsManagerService secretsManagerService) {
        this.secretsManagerService = secretsManagerService;
    }

    @PostMapping("/create-secret")
    public String createSecret(@RequestParam String secretName, @RequestParam String secretValue) {
        return secretsManagerService.createSecret(secretName, secretValue);
    }

    @PostMapping("/update-secret")
    public String updateSecret(@RequestParam String secretName, @RequestParam String secretValue) {
        return secretsManagerService.updateSecret(secretName, secretValue);
    }

    @GetMapping("/secret/{secretName}")
    public String getSecret(@PathVariable String secretName) {
        return secretsManagerService.getSecret(secretName);
    }

    @DeleteMapping("/secret/{secretName}")
    public String deleteSecret(@PathVariable String secretName) {
        return secretsManagerService.deleteSecret(secretName);
    }
}
