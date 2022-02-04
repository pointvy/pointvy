
.DEFAULT: build

build:
	docker build . -t pointvy

run-locally:
	docker run -e PORT=8080 -p 8080:8080 pointvy

deploy:
	gcloud run deploy pointvy --source .

audit:
	cd app; pipenv run pipenv check .
	bandit app/main.py

# generate new Pipfile.lock
lock:
	cd app
	pipenv lock

lint:
	flake8 app/main.py
