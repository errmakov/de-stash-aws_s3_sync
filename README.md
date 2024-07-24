# aws_s3_sync.sh

Wrapper for "aws s3 sync"d

## Installation

1. Make sure **jq**[^1] installed: `snap install jq` or `apt-get install jq`
2. Place `aws_s3_sync.sh` and `.env.aws_s3_sync.sh` to `/usr/local/scripts` or wherever.
3. Install **aws cli**
4. ``apt-get install awscli'`
5. Configure: `aws configure`
6. Obtain IAM user key & secret at [https://console.aws.amazon.com](https://console.aws.amazon.com)
7. Make sure the user runs the script has proper key and secret in `~/.aws/credentials`. It worths to set a **backup** profile or whatever, so you can use it later. Like that:

```
[backup]
aws_access_key_id = %key_id_you_obtained%
aws_secret_access_key = %secret_you_obtained%
```

8.  The AWS AIM role should has write/read access to the S3 bucket you suppose to use for backing up. It worths to create group with AWS managed role like **AWSBackupServiceRolePolicyForS3Backup**, add supposed user to it and then apply the following JSON for inline role, that restricts the user within single bucket.

```
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Action": [
				"s3:ListBucket"
			],
			"Resource": [
				"arn:aws:s3:::%s3bucket%"
			]
		},
		{
			"Effect": "Allow",
			"Action": [
				"s3:PutObject",
				"s3:GetObject",
				"s3:DeleteObject"
			],
			"Resource": [
				"arn:aws:s3:::%s3bucket%/*"
			]
		}
	]
}
```

9. Specify log file and lock file in `.env.aws_s3_sync.sh`, so the user runs the script has access to. Lock file is needed to serve concurent writing to the log file.

---

[^1]: jq is a json processor, [https://jqlang.github.io/jq/](https://jqlang.github.io/jq/)
Wed Jul 24 11:27:22 CEST 2024
Wed Jul 24 11:28:50 CEST 2024
Wed Jul 24 11:30:10 CEST 2024
