# Warrantiak: Device Warranty Checker

> `warrantiak` is a shell script to check the warranty status of devices using their serial numbers. Currently, it supports Lenovo, HP, ASUS and DELL devices, with plans to add support for DELL and Apple in the future.

<img width="1360" height="434" alt="image" src="https://github.com/user-attachments/assets/76c8cf17-b26d-483d-9468-27ac38a8841c" />


## Features

- Fetch device type and warranty information
- Display warranty start and end dates, product type, and model.
- Simple and easy-to-use command-line interface.
- Devices check: DELL, ASUS, HP, Lenovo

## Table of Contents

[**Screenshots**](#screenshots)

[**Usage**](#usage)

- [**Interactive**](#interactive)
- [**Non-interactive**](#non-interactive)
- [**Command-line arguments**](#command-line-arguments)

[**Installation**](#installation)

- [**UNIX and Linux**](#unix-and-linux)

[**System requirements**](#system-requirements)

- [**Dependencies**](#dependencies)

## Screenshots

![Bez názvu](https://github.com/user-attachments/assets/320155e8-1109-4e47-a27b-10316637342c)

## Usage

### Interactive

`warrantiak` has a built-in interactive menu that can be executed as such:

```bash
./warrantiak
```

### Non-interactive

For those who prefer to utilize command-line options, `warrantiak` also has a non-interactive mode supporting both short and long options:

```bash
./warrantiak <optional-command-to-execute-directly>
```

### Command-line arguments

Possible arguments in short and long form:

```bash
GENERATE OPTIONS
    -L, --lenovo-check
        check the warranty status of a Lenovo device
    -H, --hp-check
        check the warranty status of a HP device
    -D, --dell-check
        check the warranty status of a DELL device
    -A, --asus-check
        check the warranty status of a ASUS device

INPUT OPTIONS
    -s, --serial SN
        serial number to check; asked for if omitted
    --asus-website CODE
        ASUS country site, e.g. dk, de, uk (default global)
    --asus-base-url URL
        use another ASUS server, e.g. the local mock (default https://www.asus.com)

OUTPUT OPTIONS
    -j, --json
        print the result as JSON
    --debug
        print debug information to stderr, e.g. the raw ASUS response
    -h, --help
        show help
```

Options take precedence over the corresponding environment variables, and
values can be given as `--serial SN` or `--serial=SN`.

### Non-interactive S/N check

Pass the serial number with `-s` / `--serial`:

```bash
./warrantiak -L --serial SN123FOOBAR
```

or set the variable `_SERIAL_NUMBER`

```bash
export _SERIAL_NUMBER="SN123FOOBAR"
```

### JSON output

Add `-j` / `--json` to a check option:

```bash
./warrantiak -L --json
```

or set the variable `_JSON_OUTPUT`

```bash
export _JSON_OUTPUT="true"
```

Prompts and notices are written to stderr, so stdout contains only the JSON.

### ASUS

ASUS protects its warranty lookup with Google reCAPTCHA, so it can only be
checked from a real browser on asus.com. `warrantiak` does not bypass this:

- **Default:** the ASUS inquiry page is opened in your default browser with the
  serial number pre-filled. Accept the privacy terms and click *Submit*.
- **With Playwright installed:** a browser window opens on the ASUS page, you
  click *Submit*, and `warrantiak` prints the result in the terminal (JSON
  output supported). If ASUS rejects the lookup from the automated browser
  (`Status: FAIL`), the page is opened in your default browser instead.

```bash
pip install playwright && python3 -m playwright install chromium
```

Force a mode with `_ASUS_MODE` (`auto` (default), `browser` or `playwright`):

```bash
export _ASUS_MODE="browser"
```

Devices sold in a specific country may show *"not sold in this region"* on the
global ASUS site. Select the country site with `--asus-website` or
`_ASUS_WEBSITE` (default `global`). If that country has no warranty inquiry
page (e.g. `it`), the global page is used instead:

```bash
./warrantiak -A --serial SN123FOOBAR --asus-website dk
# or
export _ASUS_WEBSITE="dk"
```

To see the raw ASUS response, add `--debug` (or set `_ASUS_DEBUG=1`).

### Testing (ASUS mock)

`test/asus_mock` contains a local mock of ASUS' inquiry page and API that
answers from JSON fixtures per serial number. Run the tests with

```bash
make test
```

or start the mock and point `warrantiak` at it:

```bash
make mock-asus
./warrantiak -A -s 84OAAQ047369 --asus-base-url http://127.0.0.1:18765
```

See [test/asus_mock/README.md](test/asus_mock/README.md) for the fixtures and
details.

### UNIX and Linux

```bash
git clone https://github.com/be-lenka/warrantiak.git && cd warrantiak
sudo make install
```

This installs `warrantiak` to `/usr/local/bin` and the vendor libraries to
`/usr/local/share/warrantiak/lib`. Use `PREFIX` to install elsewhere, e.g.
`make install PREFIX=$HOME/.local`.

For uninstalling, open up the cloned directory and run

```bash
sudo make uninstall
```

For update/reinstall, update your clone (e.g. `git pull`) and run the command
below in the cloned directory. It removes the installed copy and installs the
local files again; nothing is downloaded.

```bash
sudo make reinstall
```

## System requirements

- An OS with a Bash shell
- Tools we use:

```bash
awk
sed
basename
cat
column
date
echo
grep
head
printf
read
```

### Dependencies

- [`bsdextrautils`](https://packages.debian.org/sid/bsdextrautils) `apt install bsdextrautils`
- [`coreutils`](https://packages.debian.org/sid/coreutils) `apt install coreutils`
- [`gawk`](https://packages.debian.org/sid/gawk) `apt install gawk`
- [`grep`](https://packages.debian.org/sid/grep) `apt install grep`

## Contribution

Want to contribute? Great! First, read this page.

### Code reviews

All submissions, including submissions by project members, require review.</br>
We use GitHub pull requests for this purpose.

### Some tips for good pull requests

- Use our code </br>
  When in doubt, try to stay true to the existing code of the project.
- Write a descriptive commit message. What problem are you solving and what
  are the consequences? Where and what did you test? Some good tips:
  [here](http://robots.thoughtbot.com/5-useful-tips-for-a-better-commit-message)
  and [here](https://www.kernel.org/doc/Documentation/SubmittingPatches).
- If your PR consists of multiple commits which are successive improvements /
  fixes to your first commit, consider squashing them into a single commit
  (`git rebase -i`) such that your PR is a single commit on top of the current
  HEAD. This make reviewing the code so much easier, and our history more
  readable.

### Formatting

This documentation is written using standard [markdown syntax](https://help.github.com/articles/markdown-basics/). Please submit your changes using the same syntax.

## Licensing

MIT see [LICENSE][] for the full license text.

[LICENSE]: https://github.com/be-lenka/warrantiak/blob/master/LICENSE

## TLDR

> If there if there is not this type off formatted output, please check your internet connection.
