PKG = template

PYTHON = python3
PYTHON_DASH_M = $(PYTHON) -m
PIP = $(PYTHON_DASH_M) pip
PIP_INSTALL = $(PIP) install

build: build-deps
	$(PYTHON_DASH_M) build

install: build
	$(PIP_INSTALL) dist/*.tar.gz

develop:
	$(PIP_INSTALL) -e '.[dev]'
	$(PYTHON_DASH_M) mypy --install-types --non-interactive --follow-imports=skip > /dev/null 2>&1

check:
	coverage run -m pytest -v tests
	coverage report -m
	coverage html

uninstall:
	$(PIP) uninstall $(PKG)

clean:
	rm -rvf dist/ build/ src/*.egg-info

push-test:
	$(PYTHON_DASH_M) twine upload --repository testpypi dist/*

pull-test:
	$(PIP_INSTALL) -i https://test.pypi.org/simple/ $(PKG)

push-prod:
	$(PYTHON_DASH_M) twine upload dist/*

pull-prod:
	$(PIP_INSTALL) $(PKG)

build-deps:
	@$(PIP_INSTALL) --upgrade pip >/dev/null
	@$(PYTHON) -c 'import build' > /dev/null 2>&1 || $(PIP_INSTALL) build
