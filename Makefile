PKG := template
PIP := python -m pip

build: build-deps
	python -m build

install: build
	$(PIP) install dist/*.tar.gz

develop:
	$(PIP) install -e '.[dev]'
	python -m mypy --install-types --non-interactive --package $(PKG) --follow-imports=skip > /dev/null 2>&1 || true

check:
	coverage run -m pytest -v tests
	coverage report -m
	coverage html

uninstall:
	$(PIP) uninstall $(PKG)

clean:
	rm -rvf dist/ build/ src/*.egg-info

push-test: push-deps
	python -m twine upload --repository testpypi dist/*

pull-test:
	$(PIP) install -i https://test.pypi.org/simple/ $(PKG)

push-prod: push-deps
	python -m twine upload dist/*

pull-prod:
	$(PIP) install $(PKG)

push-deps: build
	@python -c 'import twine' > /dev/null 2>&1 || $(PIP) install twine

build-deps:
	@$(PIP) install --upgrade pip > /dev/null
	@python -c 'import build' > /dev/null 2>&1 || $(PIP) install build
