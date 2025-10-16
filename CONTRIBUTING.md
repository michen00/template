<!-- omit in toc -->

# Regarding contributions

Welcome! We're happy to have you here. All types of contributions are encouraged and valued.

See the [Table of Contents](#table-of-contents) for different ways to help and details about how this project handles them. Please make sure to read the relevant section before making your contribution. It will make it a lot easier for us maintainers and smooth out the experience for all involved. We look forward to your contributions!

The project has defined a [code of conduct](CODE_OF_CONDUCT.md) to ensure a welcoming and friendly environment. Please adhere to it in all interactions.

<!-- omit in toc -->

## Table of Contents

- [I want to contribute](#i-want-to-contribute)
  - [Suggesting enhancements](#suggesting-enhancements)
    - [Before Submitting an Enhancement](#before-submitting-an-enhancement)
    - [How do I submit a good enhancement suggestion?](#how-do-i-submit-a-good-enhancement-suggestion)
  - [Your first code contribution](#your-first-code-contribution)
- [Creating a release](#creating-a-release)

## I want to contribute

There are many ways to contribute. Improving the documentation is no less important than improving the code of the library itself. If you find a typo in the documentation or have made improvements, do not hesitate to create a GitHub issue or preferably submit a GitHub pull request.

There are many other ways to help. In particular, improving, triaging, and investigating issues or reviewing other developers' pull requests are valuable contributions that decrease the burden on the project maintainers.

Another way to contribute is to report issues you're facing, and give a "thumbs up" on issues that others reported and that are relevant to you. It also helps us if you spread the word: reference the project from your blog and articles, link to it from your website, or simply star it in GitHub to say "I use it".

### Suggesting enhancements

This section guides you through submitting an enhancement suggestion, **including completely new features and minor improvements to existing functionality**. Following these guidelines will help maintainers and the community understand your suggestion and find related suggestions.

#### Before Submitting an Enhancement

- Make sure that you are using the latest version.
- Read the documentation carefully and find out if the functionality is already covered, maybe by an individual configuration.
- Find out whether your idea fits with the scope and aims of the project.

#### How do I submit a good enhancement suggestion?

- Use a **clear and descriptive title** for the issue to identify the suggestion.
- Provide a **step-by-step description of the suggested enhancement** in as many details as possible.
- **Describe the current behavior** and **explain which behavior you expected to see instead** and why. At this point you can also tell which alternatives do not work for you.
- You may want to **include screenshots and animated GIFs** which help you demonstrate the steps or point out the part which the suggestion is related to.
- **Explain why this enhancement would be useful** to most users. You may also want to point out other projects that solved it better and could serve as inspiration.

### Your first code contribution

Before opening a Pull Request (PR), please consider the following guidelines:

- Please make sure that the code builds perfectly fine on your local system.
- The PR must meet the code standards and conventions of the project.
- Explanatory comments related to code functions are strongly recommended.

And finally, when you are satisfied with your changes, open a new PR.

### Recommended VSCode extensions

We recommend installing the following VSCode extensions to encourage consistent code style and formatting:

- [Even Better TOML](https://marketplace.visualstudio.com/items?itemName=tamasfe.even-better-toml)
- [GitHub Actions](https://marketplace.visualstudio.com/items?itemName=GitHub.vscode-github-actions)
- [markdownlint](https://marketplace.visualstudio.com/items?itemName=DavidAnson.vscode-markdownlint)
- [MyPy Type Checker](https://marketplace.visualstudio.com/items?itemName=ms-python.mypy-type-checker)
- [Prettier - Code formatter](https://marketplace.visualstudio.com/items?itemName=esbenp.prettier-vscode)
- [Pylint](https://marketplace.visualstudio.com/items?itemName=ms-python.pylint)
- [Python](https://marketplace.visualstudio.com/items?itemName=ms-python.python)
- [Ruff](https://marketplace.visualstudio.com/items?itemName=charliermarsh.ruff)
- [ShellCheck](https://marketplace.visualstudio.com/items?itemName=timonwong.shellcheck)
- [shfmt](https://marketplace.visualstudio.com/items?itemName=mkhl.shfmt)
- [YAML](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml)

## Creating a release

1. Describe the new release in `CHANGELOG.md` (`git reset main && git pull && git cliff --unreleased`)
1. ...
