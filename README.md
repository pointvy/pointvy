# Pointvy

## Why Pointvy?

Pointvy is a simple web interface for the execution of the Trivy scanner.

Pointvy exists because sometimes (or often) you need to scan an image and:

* you don't want to or are forbidden to run Trivy on your computer.
* or you can't easily join the Internet thanks to a corporate proxy.

You define the image (optionally add some command options) and you get the result on a web page.
Pointvy is designed to run on a container serverless service based on Knative like GCP's *Cloud Run* or Scaleway's *Serverless Containers*.

You can also run it in a common Docker / Kubernetes / OpenShift environment (without Knative).

## Pointvy is not for you if

* You prefer to simply use Trivy in a console. Using [Trivy](https://aquasecurity.github.io/trivy/) would be a better choice.
* You want to automate Trivy scans in a Kubernetes cluster, then try [Starboard](https://aquasecurity.github.io/starboard/), another Aqua Security open-source project, and maybe bind it to an [Octant](https://octant.dev/) dashboard.

## Deployment of Pointvy 🚀

Several deployment options exist.

### Deploying on GCP Cloud Run

First, you need an already up and running GCP account (with billing configured). We won't cover it here.

The easiest way to run Pointvy in Cloud Run is by using `gcloud` SDK.

[Here is how to install GCP's Cloud SDK that contains `gcloud`](https://cloud.google.com/sdk/docs/install).

Clone Pointvy repository and change inside the newly created folder.

```bash
git clone https://github.com/leschard/pointvy.git

cd pointvy
```

Connect `gcloud` SDK to your GCP account.

```bash
gcloud auth login
```

Set your project ID.

```bash
gcloud config set project [your-project-ID]
```

Deploy the project to your Cloud Run tenant on GCP.

```bash
gcloud run deploy --source .
```

Instructions:

* "Service name": this will be present in the URL (simply "pointvy" may be enough).
* "Specify a region": the closest to your location might be a good choice.
* "Allow unauthenticated invocations to": Set "y" to allow people to request without requiring a GCP Cloud Identity and IAM configured. **This should only be a temporary unsecure choice.**

When the deployment has succeeded, `gcloud` will display the *Service URL* on which is exposed the service. You will get something similar to:

```bash
Building using Dockerfile and deploying container to Cloud Run service [pointvy] in project [adjective-name-334110] region [europe-north1]
✓ Building and deploying... Done.
  ✓ Uploading sources...
  ✓ Building Container... Logs are available at [https://console.cloud.google.com/cloud-build/builds/9733bbcb-0000-0000-0000-df0772559fa3?project=437000000103].
  ✓ Creating Revision...
  ✓ Routing traffic...
Done.
Service [pointvy] revision [pointvy-00003-kix] has been deployed and is serving 100 percent of traffic.
Service URL: https://pointvy-7oaxxxxxxnq-lz.a.run.app
```

⚠️ Do not try to use the URL that are present in this example. They won't work.

⚠️ Keep in mind that the execution of the container in Cloud Run and the storage of its image in your GCP Registry **is not free!**
Depending on your configuration, the service might allow direct and unauthenticated access to anybody from the Internet. Other people might use it as soon as they know the URL and might increase your bill.

### Deploying on Scaleway Serverless Containers

Clone Pointvy repository.

```bash
git clone https://github.com/leschard/pointvy.git
```

As Scaleway doesn't provide a container building pipeline, you have to build the Pointvy container on your side.

```bash
docker build . -t pointvy
```

Export locally your secret token that you previously created in the [credentials section](https://console.scaleway.com/project/credentials).

```bash
export SCW_SECRET_TOKEN="value of your password"
```

Export the name of your namespace:
⚠️ Of course, replace `[name-of-your-registry-namespace]` with the name of a namespace you previously created in Scaleway Container Registry.

```bash
export NAMESPACE=[name-of-your-registry-namespace]
```

Connect Docker to the registry:

```bash
docker login rg.fr-par.scw.cloud/${NAMESPACE} -u nologin -p ${SCW_SECRET_TOKEN}
```

Locally tag the recently built pointvy image with the path to your registry.

```bash
docker tag pointvy:latest rg.fr-par.scw.cloud/${NAMESPACE}/pointvy:latest
```

Push the image you just tagged to your remote Container Registry.

```bash
docker push rg.fr-par.scw.cloud/${NAMESPACE}/pointvy:latest
```

💡 You can't use Docker Hub as a registry or any other public registry.

Finally, deploy the container by using the [web console > Serverless Container](https://console.scaleway.com/containers/namespaces).

The container endpoint will be displayed in the console and be similar to [https://pointvyxxxxxxxx-pointvy.functions.fnc.fr-par.scw.cloud/](https://pointvyxxxxxxxx-pointvy.functions.fnc.fr-par.scw.cloud/).

⚠️ As for GCP Cloud Run, keep in mind that the use of resources is not free. If unauthenticated access to your endpoint is allowed, people may increase your bill.

### Docker

Clone Pointvy repository.

```bash
git clone https://github.com/leschard/pointvy.git
```

```bash
docker build . -t pointvy
```

```bash
docker run -p 8080:8080 -e PORT=8080 pointvy
```

⚠️ **the full `-p 8080:8080 -e PORT=8080` expression *must* be present otherwise the gunicorn server won't be bound to the right TCP port and/or won't be exposed on the good port.**

The interface should be reachable at [http://localhost:8080](http://localhost:8080) if you run it locally and depends on your configuration if you run it on a remote server.

Keep in mind that direct Internet access is required by the container in order to download the vulnerabilities database.

## Contributing

Feel free to send PR to add modifications that you would share and see included in this open-source project.

---

Pointvy is an open-source project that uses Trivy but <b>is not</b> affiliated with, funded by, or associated with Aqua Security.
