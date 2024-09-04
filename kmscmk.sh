export REGION=us-west-2
export KEY_ALIAS=kmsCmkdemo1

export KEY_ID=`aws kms create-key --region $REGION --origin EXTERNAL --description $KEY_ALIAS --query KeyMetadata.KeyId --output text`

aws kms --region $REGION create-alias --alias-name alias/$KEY_ALIAS --target-key-id $KEY_ID


aws kms --region $REGION describe-key --key-id $KEY_ID



export KEY_PARAMETERS=`aws kms --region $REGION get-parameters-for-import --key-id $KEY_ID --wrapping-algorithm RSAES_OAEP_SHA_256 --wrapping-key-spec RSA_2048` 
echo $KEY_PARAMETERS | awk '{print $7}' | tr -d '",' | base64 --decode > PublicKey.bin
echo $KEY_PARAMETERS | awk '{print $5}' | tr -d '",' | base64 --decode > ImportToken.bin

openssl rand -out PlaintextKeyMaterial.bin 32
openssl pkeyutl -in PlaintextKeyMaterial.bin -out EncryptedKeyMaterial.bin -inkey PublicKey.bin -keyform DER -pubin -encrypt -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256
aws kms --region $REGION import-key-material --key-id $KEY_ID --encrypted-key-material fileb://EncryptedKeyMaterial.bin --import-token fileb://ImportToken.bin --expiration-model KEY_MATERIAL_DOES_NOT_EXPIRE
