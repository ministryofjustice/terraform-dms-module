package test

import (
    "os"
    "strings"
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
)

func TestRootModule(t *testing.T) {
    // Skip entirely if SKIP_TERRAFORM_TESTS=true
    if os.Getenv("SKIP_TERRAFORM_TESTS") == "true" {
        t.Skip("Skipping Terraform tests because SKIP_TERRAFORM_TESTS is set")
    }

    terraformOptions := &terraform.Options{
        TerraformDir: "..",

        VarFiles: []string{
            "test/fixtures/root.auto.tfvars.json",
        },

        BackendConfig: map[string]interface{}{
            "assume_role": `{"role_arn":"arn:aws:iam::042130406152:role/data-engineering-state-access"}`,
        },

        NoColor: true,
    }

    // Run init + plan but handle AWS missing cred errors gracefully
    planOutput, err := terraform.InitAndPlanE(t, terraformOptions)
    if err != nil {
        msg := err.Error()

        // These errors mean AWS isn't configured → skip, not fail
        if strings.Contains(msg, "No valid credential sources found") ||
            strings.Contains(msg, "InvalidGrantException") ||
            strings.Contains(msg, "could not assume role") ||
            strings.Contains(msg, "expired") {
            t.Skipf("Skipping plan due to missing/invalid AWS credentials: %v", err)
            return
        }

        // Missing provider config → also skip
        if strings.Contains(msg, "requires explicit configuration") {
            t.Skipf("Skipping plan due to missing AWS provider configuration: %v", err)
            return
        }

        // Any other error means your Terraform module is actually broken
        t.Fatalf("Unexpected terraform error: %v", err)
    }

    // If we get here, plan succeeded!
    t.Log("Terraform plan succeeded")
    t.Log(planOutput)
}
