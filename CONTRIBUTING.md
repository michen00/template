<!-- omit in toc -->

# Regarding contributions

All types of contributions are encouraged and valued. See the [Table of Contents](#table-of-contents) for different ways to help and details about how this project handles them. Please make sure to read the relevant section before making your contribution. It will make it a lot easier for us maintainers and smooth out the experience for all involved. We look forward to your contributions!

The project has defined a [code of conduct](CODE_OF_CONDUCT.md) to ensure a welcoming and friendly environment. Please adhere to it in all interactions.

## TODO

- video demos

- improve test coverage
- use matrix python versions in CI
- audit and review tests
- define custom exceptions
- define TypedDicts for script default configs
- distribute via CloudSmith (or PyPI)
- update names to be can-agnostic

<!-- omit in toc -->

## Table of Contents

- [I want to contribute](#i-want-to-contribute)
  - [Suggesting enhancements](#suggesting-enhancements)
    - [Before Submitting an Enhancement](#before-submitting-an-enhancement)
    - [How do I submit a good enhancement suggestion?](#how-do-i-submit-a-good-enhancement-suggestion)
  - [Your first code contribution](#your-first-code-contribution)
- [Creating a release](#creating-a-release)

## I want to contribute

### Suggesting enhancements

This section guides you through submitting an enhancement suggestion, **including completely new features and minor improvements to existing functionality**. Following these guidelines will help maintainers and the community understand your suggestion and find related suggestions.

#### Before Submitting an Enhancement

- Make sure that you are using the latest version.
- Read the documentation carefully and find out if the functionality is already covered, maybe by an individual configuration.
- Find out whether your idea fits with the scope and aims of the project. Keep in mind that we want features that will be useful to the majority of our users and not just a small subset.

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

## Creating a release

1. Describe the new release in `CHANGELOG.md` (`git reset main && git pull && git cliff --unreleased`)
1. TODO: finish this section
