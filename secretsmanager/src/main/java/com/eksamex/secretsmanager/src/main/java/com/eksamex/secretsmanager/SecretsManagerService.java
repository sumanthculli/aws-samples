package com.eksamex.secretsmanager;

import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.*;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;

@Service
public class SecretsManagerService {

    private SecretsManagerClient secretsManagerClient= SecretsManagerClient.builder().region(Region.US_WEST_2).build();

    public String createSecret(String secretName, String secretValue) {
        Map<String, String> secretData = new HashMap<>();
        secretData.put("username", "myusername");
        secretData.put("password", "mypassword");

        // Convert the map to a JSON string
        String secretString = "{\"username\":\"" + secretData.get("username") + "\",\"password\":\"" + secretData.get("password") + "\"}";

        CreateSecretRequest createSecretRequest = CreateSecretRequest.builder()
                .name(secretName)
                .secretString(secretString)
                .build();

        CreateSecretResponse createSecretResponse = secretsManagerClient.createSecret(createSecretRequest);
        return createSecretResponse.arn();
    }


    public String updateSecret(String secretName, String secretValue) {
        Map<String, String> secretData = new HashMap<>();
        secretData.put("username", "myusername");
        secretData.put("password", "mypassword1");

        // Convert the map to a JSON string
        String secretString = "{\"username\":\"" + secretData.get("username") + "\",\"password\":\"" + secretData.get("password") + "\"}";

        UpdateSecretRequest updateSecretRequest = UpdateSecretRequest.builder().
                secretId(secretName)
                .secretString(secretString)
                .build();

        UpdateSecretResponse updateSecretResponse = secretsManagerClient.updateSecret(updateSecretRequest);
        return updateSecretResponse.arn();
    }


    public String getSecret(String secretName) {
        GetSecretValueRequest getSecretValueRequest = GetSecretValueRequest.builder()
                .secretId(secretName)
                .build();
        GetSecretValueResponse getSecretValueResponse = secretsManagerClient.getSecretValue(getSecretValueRequest);
        return "Secret retrieved: " + getSecretValueResponse.secretString();
    }

    public String deleteSecret(String secretName) {
        DeleteSecretRequest deleteSecretRequest = DeleteSecretRequest.builder()
                .secretId(secretName)
                .recoveryWindowInDays(7L)
                .build();

        DeleteSecretResponse deleteSecretResponse = secretsManagerClient.deleteSecret(deleteSecretRequest);
        return "Secret scheduled for deletion: " + deleteSecretResponse.name();

    }

}
