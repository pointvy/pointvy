
.DEFAULT: build
.PHONY: build run-locally deploy audit lock lint dockerfile smoke unit

build:
	docker build . -t pointvy

run-locally:
	docker run -e PORT=8080 -p 8080:8080 pointvy

# build the image and run the container smoke/security tests
smoke:
	./tests/smoke.sh

# unit tests (Trivy mocked, no Docker needed)
unit:
	cd app && uv run --locked pytest

deploy:
	gcloud run deploy pointvy --source .

audit:
	cd app && uv pip check
	bandit app/main.py

# generate new uv.lock
lock:
	cd app && uv lock

lint:
	flake8 app/main.py

dockerfile:
	./generate-dockerfile.sh
	mv Dockerfile Dockerfile.bak
	mv Dockerfile.latest Dockerfile
