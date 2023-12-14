PKG = template

build:
	python3 -m pip install --upgrade pip
	python3 -m pip install build
	python3 -m build

install: build
	python3 -m pip install dist/*.tar.gz

develop:
	python3 -m pip install -e '.[dev]'
	python3 -m mypy --install-types

check:
	python3 -m pytest -v tests

uninstall:
	python3 -m pip uninstall $(PKG)

clean:
	rm -rvf dist/ build/ src/*.egg-info

push-test:
	python3 -m twine upload --repository testpypi dist/*

pull-test:
	python3 -m pip install -i https://test.pypi.org/simple/ $(PKG)

push-prod:
	python3 -m twine upload dist/*

pull-prod:
	python3 -m pip install $(PKG)
