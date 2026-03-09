# https://aarongorka.com

  * https://gohugo.io/
  * https://github.com/carsonip/hugo-theme-minos
  * https://photoswipe.com/
  * [GitLab CI/CD](https://gitlab.com/aarongorka/aarongorka-com/-/pipelines)
  * [AWS CloudFront, S3 and Lambda@Edge](cloudformation.yaml)
  * 🪦 ~https://3musketeers.io/~

## Deploying

1. Install [Hugo](https://gohugo.io/installation/)
2. Clone the repo, critically with submodules to get the theme too
    ```bash
    git clone --recursive https://github.com/aarongorka/aarongorka-com

    ```
3. Build the site (note: if building under an alternate domain, modify `baseURL` in `config.yaml` or links won't work)
    ```bash
    hugo
    ```
4. Deploy the CloudFormation stack. This assumes you have an existing cert in ACM.
    ```bash
    CERTIFICATE_ARN="<ARN to an ACRM certificate>"
    DOMAIN_NAME="<your domain name>"
    aws cloudformation create-stack \
        --region us-east1 \
        --stack-name aarongorka-com \
        --template-body file://cloudformation.yaml \
        --parameters ParameterKey=DomainName,ParameterValue=$DOMAIN_NAME ParameterKey=CertificateArn,ParameterValue=$CERTIFICATE_ARN
    ```
5. Sync the contents of the website to the bucket
    ```bash
    aws s3 sync --no-progress --delete --cache-control 'max-age=3155695200' public/ "s3://${DOMAIN_NAME}/"
    ```
6. Manually (or otherwise through another mechanism) create A and AAAA records for `$DOMAIN_NAME` pointing to the `CloudFrontDistributionDomainName`
