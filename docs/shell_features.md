# Notes on shell feautres used in these scripts

These explanations are how I understand the shell to work, and may not necessarily match up with either [the specification for that behaviour][shell specification], or the implemented behaviour.

These notes are mainly for my future self.

## No strings

POSIX shell `"` and `'` don't delimit strings, and instead, in most cases, change the way word splitting is done. For example, the following two command invocations are very likely to print out the same thing:

```sh
echo "hello world"
echo hello" w"orld
```

The best explanation I've heard of them is as toggles: they toggle different ways the interpreter considers special characters (metacharacters) and reserved words.

The shell does not much care where these toggles happen, only which state it's in, and which state it's transitioning to.

### `"` and `'`

`"` allows:

- parameter expansion: `"${PARAMETER}"`
- command substitution: `"$(echo 'command running in a string with stdout being captured as the value of this expansion')"`
- arithmetic expansion: `"$(( $? + 1 ))"`

In this mode, `\` can be used still to escape special characters. Additionally, `'` is a literal character.

`'` causes every character to be treated as a literal character, except `'`, which toggles back.

To insert a `'` somewhere, it needs to be quoted, either by escaping it with a backslash, or by quoting it with `"`:

```sh
echo this\'ll work
echo "this is 'fine'"
```

This is also why getting a quoted `'` inside `'` looks so weird:

```sh
echo 'This '"'"' <- is a single single-quote'
# This ' <- is a single single-quote
```

In `'"'"'`, the first `'` toggles out of single-quotes mode back to normal mode, the `"` then toggles to double-quotes mode, then a `'` can be included without having to quote it. `"` toggles back to normal mode, then finally the last `'` toggles back to single-quotes mode. Because no word-splitting characters (e.g whitespace) were inserted between any `'` or `"` in normal mode, this is treated as a contiguous word with the parts before and after (e.g. `he""llo` is treated as one word).

Because the goal is to quote a `'`, any way of doing that works, the above is just the easiest to programmatically nest. The following is the same for a single-quoted string:

```sh
echo 'This '\'' <- is a single single-quote'
# This ' <- is a single single-quote
```

Multiline values need no special escaping or syntax, as `"` and `'` also quote the newline character, allowing it to be included in the argument:

```sh
echo "first line
second line"
# first line
# second line
echo 'works the
same way'
# works the
# same way
```

Escaping the newline character inside double quotes eliminates it:

```sh
echo "all \
one \
line"
# all one line
```

Note that the newline character cannot be escaped in `'`, since the excaping character `\` is treated as a literal character. To span an argument over multiple lines while using `'`, something like this can be used:

```sh
echo 'The first part,' \
     'then the second part'
# The first part, then the second part
```

> _Note: `echo` adds a space between each of it's arguments_

Outside of quotes, the newline character can be escaped with `\` to continue a command onto a new line:

```sh
echo "just a very long" \
    "command and not two separate commands"
# just a very long command and not two separate commands
```

Note that a command can be quoted, and will still be run, if it's in the spot a command would be:

```sh
"echo" hello, world\!
# hello, world!
```

This lets commands be stored in variables, which is useful if the command has different names on different platforms:

```sh
if command -v "python" ; then
    PYTHON="python"
elif command -v "python3" ; then
    PYTHON="python3"
else
    echo "no python found"
fi
"${PYTHON}" -c 'print("hello, world!")'
# hello, world!
```

## [Parameter expansion][]

[Shell parameter expansion][parameter expansion] can be modified inside braces:

```sh
TEMP_VAR=""
echo "TEMP_VAR is ${TEMP_VAR:-"not set or empty"}"
```

The above example sets the environment variable named `TEMP_VAR` to an empty string (also referred to as null), and then the parameter expansion checks if it's unset or null, and it's value is replaced with the single value `not set or empty`, which is printed to stdout.

In general, it's a good idea to quote things that are intended to be text, and to quote parameter expansions and command substitutions, to prevent weirdness:

```sh
ENV_VAR='hello * oops'
echo ${ENV_VAR}
```

prints most of the files in the directory in which this is run.

Also, note that quoting a command substitution _**does not**_ quote parameter expansions in that command substitution:

```sh
ENV_VAR='hello * oops'
echo "$(echo ${ENV_VAR})"
```

still prints out most of the files.

### Parameter expansion modifications

Parameter expansions can be modified by including special characters inside the `{}`, along with the name of the parameter. The table below is recreated from the standard, and is one I find myself referencing very frequently:

| Modification                                   | _parameter_ set and not NULL | _parameter_ set but NULL | _parameter_ unset   |
|------------------------------------------------|------------------------------|--------------------------|---------------------|
| <pre>${parameter<strong>:-</strong>word}</pre> | substitute _parameter_       | substitute **word**      | substitute **word** |
| <pre>${parameter<strong>-</strong>word}</pre>  | substitute _parameter_       | substitute NULL          | substitute **word** |
| <pre>${parameter<strong>:=</strong>word}</pre> | substitute _parameter_       | assign **word**          | assign **word**     |
| <pre>${parameter<strong>=</strong>word}</pre>  | substitute _parameter_       | substitute NULL          | assign **word**     |
| <pre>${parameter<strong>:?</strong>word}</pre> | substitute _parameter_       | error, exit              | error, exit         |
| <pre>${parameter<strong>?</strong>word}</pre>  | substitute _parameter_       | substitute NULL          | error, exit         |
| <pre>${parameter<strong>:+</strong>word}</pre> | substitute **word**          | substitute NULL          | substitute NULL     |
| <pre>${parameter<strong>+</strong>word}</pre>  | substitute **word**          | substitute **word**      | substitute NULL     |

In the table above:

- _parameter_ is most likely the name of an environment variable
- **word** can be almost any expression that results in a string of text
- NULL appears to be synonymous with the empty string (`""`) in POSIX

_note: it's probably a good idea to quote **word** so that it's not expanded to anything weird_

_note: it is valid to use an empty string for **word** (e.g. `${parameter:-}` to substitute NULL if the parameter is NULL or not set)_

Additionally, there's `${#parameter}`, which substitutes the string length of _parameter_, with the caveat that `${#*}` and `${#@}` are both unspecified.

The [specification's section on parameter expansion][parameter expansion] lists more expansions, including some that allow prefix and suffix removal (e.g. `${parameter%/*}` for removing everything after the last `/` in a path, though `dirname` is the more appropriate utility for this).

## Special parameters

Some variables are defined by the shell (section 2.5.2 Special Parameters):

- `$@`: all of the parameters passed to the shell script or function, maintaining their original word splitting
- `$#`: the decimal number of parameters in `$@`
- `$?`: the exit code returned by the most recent command
- `$!`: the provess ID of the most recent backgrounded command
- `$1`-`$9`: the first through ninth position parameters passed to the shell script or function (may not be set if no parameters were passed)

Others are, too, but those are the main ones these scripts use.

They can be used in brace-delimited parameter expansions, but sometimes the behaviour is not well-defined. Frequently, they are used as given here.

[Section C.2.5 of this version of the specification][`$@` and `$*` examples] has a lot of useful examples of how `$@` behaves, along with other shell variables, recreated below:

```sh
set "abc" "def ghi" "jkl"
unset novar
IFS=' ' # a space
printf '%s\n' $*
# abc
# def
# ghi
# jkl
printf '%s\n' "$*"
# abc def ghi jkl
printf '%s\n' xx$*yy
# xxabc
# def
# ghi
# jklyy
printf '%s\n' "xx$*yy"
# xxabc def ghi jklyy
printf '%s\n' $@
# abc
# def
# ghi
# jkl
printf '%s\n' "$@"
# abc
# def ghi
# jkl
printf '%s\n' ${1+"$@"}
# abc
# def ghi
# jkl
printf '%s\n' ${novar-"$@"}
# abc
# def ghi
# jkl
printf '%s\n' xx$@yy
# xxabc
# def
# ghi
# jklyy
printf '%s\n' "xx$@yy"
# xxabc
# def ghi
# jklyy
printf '%s\n' $@$@
# abc
# def
# ghi
# jklabc
# def
# ghi
# jkl
printf '%s\n' "$@$@"
# abc
# def ghi
# jklabc
# def ghi
# jkl

IFS=':'
printf '%s\n' "$*"
# abc:def ghi:jkl
var=$*; printf '%s\n' "$var"
# abc:def ghi:jkl
var="$*"; printf '%s\n' "$var"
# abc:def ghi:jkl
unset var
printf '%s\n' ${var-$*}
# abc
# def ghi
# jkl
printf '%s\n' "${var-$*}"
# abc:def ghi:jkl
printf '%s\n' ${var-"$*"}
# abc:def ghi:jkl
printf '%s\n' ${var=$*}
# abc
# def ghi
# jkl
printf 'var=%s\n' "$var"
# var=abc:def ghi:jkl
unset var
printf '%s\n' "${var=$*}"
# abc:def ghi:jkl
printf 'var=%s\n' "$var"
# var=abc:def ghi:jkl

IFS='' # null
printf '%s\n' "$*"
# abcdef ghijkl
var=$*; printf '%s\n' "$var"
# abcdef ghijkl
var="$*"; printf '%s\n' "$var"
# abcdef ghijkl
unset var
printf '%s\n' ${var-$*}
# abcdef ghijkl
printf '%s\n' "${var-$*}"
# abcdef ghijkl
printf '%s\n' ${var-"$*"}
# abcdef ghijkl
printf '%s\n' ${var=$*}
# abcdef ghijkl
printf 'var=%s\n' "$var"
# var=abcdef ghijkl
unset var
printf '%s\n' "${var=$*}"
# abcdef ghijkl
printf 'var=%s\n' "$var"
# var=abcdef ghijkl
printf '%s\n' "$@"
# abc
# def ghi
# jkl

unset IFS
printf '%s\n' "$*"
# abc def ghi jkl
var=$*; printf '%s\n' "$var"
# abc def ghi jkl
var="$*"; printf '%s\n' "$var"
# abc def ghi jkl
unset var
printf '%s\n' ${var-$*}
# abc
# def
# ghi
# jkl
printf '%s\n' "${var-$*}"
# abc def ghi jkl
printf '%s\n' ${var-"$*"}
# abc def ghi jkl
printf '%s\n' ${var=$*}
# abc
# def
# ghi
# jkl
printf 'var=%s\n' "$var"
# var=abc def ghi jkl
unset var
printf '%s\n' "${var=$*}"
# abc def ghi jkl
printf 'var=%s\n' "$var"
# var=abc def ghi jkl
printf '%s\n' "$@"
# abc
# def ghi
# jkl

set one "" three
printf '[%s]\n' $*
# [one]
# [] (this line of output is optional)
# [three]
printf '[%s]\n' $@
# [one]
# [] (this line of output is optional)
# [three]

set --
printf '[%s]\n' foo "$*"
# [foo]
# []
printf '[%s]\n' foo "$novar$*$(echo)"
# [foo]
# []
printf '[%s]\n' foo $@
# [foo]
printf '[%s]\n' foo "$@"
# [foo]
printf '[%s]\n' foo ''$@
# [foo]
# []
printf '[%s]\n' foo ''"$@"
# [foo]
# []
printf '[%s]\n' foo "$novar$@$(echo)"
# [foo]
# [] (this line of output is optional)
printf '[%s]\n' foo ''"$novar$@$(echo)"
# [foo]
# []
```

## User-defined functions

Different shells allow for varying syntaxes for defining functions. The one that these scripts use appears to be the one most common to all implementations:

```sh
function_name() {
    # function does stuff
}
```

The function is executed with the same syntax as shell builtins like `echo`:

```sh
function_name
```

or

```sh
function_name "first parameter" "second parameter"
```

Inside the function, `$#`, `$@`, `$1`, etc are redefined as if the context inside the function was instead a shell script that was called with the same positional parameters.

Functions do not have to explicitly return anything. If they don't, they exit with the exit code of the last command.

They can call `exit`, which will exit the shell the function is run in, or `return`, which is only valid inside a function, and doesn't exit the entire shell.

Even though `$1` and `$@` and such are reset inside a function, the rest of the environment is not:

```sh
a_function() {
    VAR="hello"
}
a_function
echo "${VAR}"
```

Functions can also be exported, just like variables.

## Command substitution

The text delimited by `$(` and `)` runs in a sub-shell. The exit code of the subshell is the exit code of the last command run in it:

```sh
ENV_VAR="$(exit 1)" # A variable assignment does not modify $?
echo "$?"
# 1
```

The stdout of the subshell is the value the command substitution is replaced with:

```sh
echo "$(false && echo yes || echo no)"
# no
```

Command substitution can be nested, if need be:

```sh
echo "current directory is named '$(basename "$(dirname "$(pwd)")")'"
```

## Arithmetic expansion

Inside arithmetic expansions, parameter expansion is performed without a leading `$`:

```sh
A=1
echo "$(( A + 1 ))"
# 2
```

Note that both `$(( 1 == 1 ))` and `$(( 2 == 1 ))` return an exit code of `0`. `test 1 -eq 2` is the correct way to check equality of numbers.

## Shell builtins

Some notes on selected shell builtins:

- [`echo`][echo builtin]: POSIX defines this as taking no arguments, and always interpreting some escape sequences, like `\n` as a carriage return
  - This can be cause problems when using `echo` to pipe to [`jq`][jq]
- [`command`][command builtin]: normally runs the specified command, but has a `-v` flag that prints the location of the command, and is useful for testing if it's available
- [`test` or `[`][test builtin]: they almost the same, and perform a variety of tests for filesystem conditions, and string and numeric comparisons
  - `[` requires that a single `]` be at the end of every list of parameters; `test` does not
  - Provides `-a` and `-o` for stringing together conditional expressions, but `shellcheck` points out that this is not well-defined between different shells
- [`:`][colon builtin]: does nothing, always exits with `0`, regardless of what arguments are given to it
- [`exec`][exec builtin]: executes the command, and optionally some arguments, replacing the current shell with that command
- [`eval`][eval builtin]: concatenates its arguments with spaces and executes the text with the current shell environment, letting modifications be made to it
- [`.`][dot builtin]: executes commands in the named file in the current environment, with the first argument being a path pointing to said file
  - If the path is relative, it should explicitly start with `./`, otherwise similarly-named files in the `PATH` might be run instead
- [`export`][export builtin]: marks the variable to be exported to subshells (can optionally set the initial value if the variable named is followed by `=`, but it sets its own exit code so it's best to export variables as a separate command)
- [`read`][read builtin]: reads input from stdin, and sets the variable named in its first positional parameter with the result; is used to ask for the user to type information
- [`set`][set builtin]:
  - sets shell options (e.g. `set -e` turns on "exit if any command returns anything other than `0`, `set +e` turns it off)
  - sets the values of positional parameters (e.g. `set -- a b c` -> `$2` is `b`)
  - without arguments prints everything set in the current shell
  - `set +o` prints all the currently set shell options in a way that can be saved and `eval`ed later
- [`trap`][trap builtin]: allows catching signals sent to the shell, and running functions in response (e.g. <kbd>Control+\</kbd> sends `SIGQUIT`, `stty -a` may print others)
- [`unset`][unset builtin]: unsets variables and functions; `-v` and `-f` disambiguate which is meant if the same name is used for both
- [`printf`][printf builtin]: writes to stdout strings interpolated using a syntax similar to C's same-named function

`[` is a function, usually a shell builtin, but also may not be (i.e. it may be a binary executable in the `PATH`). It takes as arguments an expression. This expression must be ended with a positional parameter of `]`. This creates the illusion in the shell of a `[ <conditional> ]` syntax, when in reality, it's the same as running a command like `test <conditional>`.

One consequence of this is that `]` has to be in its own word: `[a=a]` does not work, and neither does `[ a=a]` or `[ a = a]`. Only `[ a = a ]` works properly everywhere.

The same thing goes for the operators, since they are passed as strings to the `[` command: `[ a =a ]` does not work, as it's not clear if `=a` is its own string, or if it's `=` and `a`.

Some common conditionals:

- `-n`: is the string 1 or more characters long?
- `-z`: is the string empty?
- `=`: are the two strings the same?
- `!=`: are the two strings different?
- `-eq`: expects the arguments to be decimal numbers, and returns `0` if their values are the same
- `-ne`: not equal
- `-gt`: greater than
- `-ge`: greater than or equal to
- `-lt`: less than
- `-le`: less than or equal to
- `-f`: string is a path to a file that exists
- `-d`: string is a path to a directory that exists
- `-r`: string is a path to a file that has read permissions set for this user

Examples:

```sh
[ -f "/path/to/file.txt" ]
test "$#" -gt 0
[ "${SHELL}" = "sh" ]
```

### External commands

I try not to use too many external commands, but unfortunately the POSIX shell can't do everything.

The biggest ones are [LXD][]'s client, `lxc`, and [`jq`][jq]. For [`jq`][jq] specifically, version 1.5 is that's what's in the Debian 10 repositories, which is what this was developed on. Fortunately, the features the scripts rely on are pretty common, and forward-compatible.

[`basename`][basename] is a small one, which takes as text a path to a file, and returns just the filename, without the directories:

```sh
basename a/b/c.txt
# c.txt
```

It could be replaced with clever use of parameter expansion prefix trimming (e.g. `${parameter##*/}`, note that the glob `*` in the expansion is treated as a literal character if it's quoted).

There's also [`date`][date], which prints and can format the current date and time.

Most systems with a POSIX shell have those commands.

Some others that were used, but aren't anymore:

- [`dirname`][dirname]: `/path/to/file.txt` -> `/path/to` (opposite of `basename`)

## Control flow

The main ones are:

- `if / then / else`
- `case`
- `for`
- `while`

Note that each of the control statements doesn't take a conditional, it takes a command list. If the return code of the command list is `0`, it's considered "true", and the command list after `then` is run. If it's anything else, that second command list after `then` is skipped.

The shell keyword `!` can help here: when preceding a pipeline or command list, it makes a non-zero exit status `0` into an exit status of `0`, and one of `0` into `1`.

Also, most control flow statements allow command lists and pipelines to fail by returning a non-zero exit status, without exiting the whole script, even when `set -e` is in effect:

```sh
set -e
if false; then
    echo "uh oh"
else
    echo "The script continues to run"
fi

false

echo "This is not printed"
```

### [`if / then / else`][if statement]

```sh
if <command-list>; then
    <command-list>
elif <command-list>; then
    <command-list>
else
    <command-list>
fi
```

The command list after `if`, `then`, `elif`, and `else` must be terminated, either with an unquoted newline, or a `;`. Like any other command list, it can span multiple lines, using any continuation mechanism:

```sh
if : "like echo but" \
     "doesn't print"
then <command-list>
elif <command-list>
then <command-list>
else <command-list>
fi
```

As one-liners:

```sh
if true ; then echo "true!" ; elif false ; then echo "false?" ; else echo "how???" ; fi
```

### [`case`][case statement]

```sh
case <text-to-match> in
    <pattern>)
        <command-list>
        ;;
esac
```

For `case`, the `<pattern>` appears to be the one used for matching file names:

- `*` matches 0 or more characters
- `?` matches any 1 character
- `[a-z]` matches the letters from `a` through to `z`, inclusive, and case-sensitive
  - To specify non-matches, instead of `[^q]` it's `[!q]`

### [`for`][for loop]

```sh
for variable_name in <words>; do
    echo "${variable_name}"
done
```

Because `<words>` is created using shell word splitting, this is one are where leaving command substitutions unquoted is useful:

```sh
for word in $(seq 3); do
    echo "${word}"
done
# 1
# 2
# 3
```

It should be noted that it doesn't seem to care if the words result in parameters separated by spaces or newlines. This is probably defined in the description of word splitting.

It should also be noted that the quoting rules for `$@` are great here, as it maintains the arguments as they were passed in:

```sh
example() {
    for file in "$@" ; do
        if [ -r "${file}" ]; then
            echo "can read ${file}"
        else
            echo "${file} is not readable"
        fi
    done
}
TEMP_DIR="$(mktemp -d)"
touch "${TEMP_DIR}/has two spaces.txt"
touch "${TEMP_DIR}/includes * pattern ? characters.txt"
chmod a-r "${TEMP_DIR}/has two spaces.txt"
chmod a+r "${TEMP_DIR}/includes * pattern ? characters.txt"
example "${TEMP_DIR}/"*
# /tmp/tmp.WYoqODrnlj/has two spaces.txt is not readable
# can read /tmp/tmp.WYoqODrnlj/includes * pattern ? characters.txt
rm -r "${TEMP_DIR}"
```

### [`while`][while loop]

```sh
while <command-list>; do
    <command-list>
done
```

The command-list after `while` is run each loop. If it has an exit code of `0`, the command-list after `do` is run. `break` is a great keyword to exit infinite loops.

## Common patterns

These are common patterns I've used in these scripts, and while the explanations above can be pieced together to understand them, this is a quick reference for them.

The site <https://explainshell.com/> can be very helpful in understanding more compound expressions.

### `set -eu`

Causes the shell to exit if any command returns a non-zero exit code, and if any parameter is reference when it's not set.

I use this to help catch things that are probably errors in code.

The letters can appear in any order.

### `set +eu`

Turns off the checks mentioned in the previous section.

### `[ -n "${parameter:+"set"}" ]`

The inner expression `${parameter:+"set"}` will return `set` if the environment variable `parameter` is set, and an empty string otherwise. The surrounding `"` are not strictly necessary, as the expression will only ever expand to either `set` or an empty string, but feel like a good idea.

`[ -n string ]` tests if the string is not empty.

So this is "if _parameter_ is set.

For example:

```sh
set -eu
VARIABLE="environment variable is set, and contains text"

if [ -n "${VARIABLE:+"set"}" ]; then
    echo "variable is set"
else
    echo "variable is not set"
fi

unset -v VARIABLE

if [ -n "${VARIABLE:+"set"}" ]; then
    echo "variable is set"
else
    echo "variable is not set"
fi
```

The above will print:

```text
variable is set
variable is not set
```

### `[ -z "${parameter:+"unset"}" ]`

As above, the inner expression `${parameter:+"unset"}` expands to an empty string if _parameter_ is unset or an empty string, and `unset` otherwise.

In this case, `[ -z string ]` tests if the string is empty, so the **word** portion of the parameter expansion is `unset` as a visual reminder that this will execute the `then` section of an `if` statement.

```sh
set -eu
VARIABLE="environment variable is set, and contains text"

if [ -z "${VARIABLE:+"unset"}" ]; then
    echo "variable is not set"
else
    echo "variable is set"
fi

unset -v VARIABLE

if [ -z "${VARIABLE:+"unset"}" ]; then
    echo "variable is not set"
else
    echo "variable is set"
fi
```

The above will print:

```text
variable is set
variable is not set
```

### `command1 && command2 || command3`

POSIX shell short circuits the `&&` and `||`, so this runs `command1`, and, depending on the exit status, runs `command2` if it's `0`, or `command3` if it's something else. This can be useful, since the whole pipeline is treated as a single command for the purposes of `set -e`, so `command1` can fail, and can be responded to:

```sh
set -eu

true  && echo "command succeeded" || echo "command failed"
false && echo "command succeeded" || echo "command failed"
```

Prints:

```text
command succeeded
command failed
```

### Extra `x` in `test` or `[` string comparison

```sh
[ "x${parameter}x" = "x${parameter}x" ]
```

The extra `x` in a string comparison can "guard" the expansion, as they attach to the first and last word of the expansion. This helps if the parameters may contain characters that, on their own, would be interpreted as special by `test` or `[`:

```sh
A="="
B="="
if [ "${A}" = "${B}" ]; then
    echo strings are equal
else
    echo strings are not equal
fi
```

In some shells, the above may cause an error.

This is because the `test` expression expands to:

```sh
if [ = = = ]; then
```

Which some shells have difficulty interpreting. The extra `x` prevent the `=` from being treated specially.

It looks like `[` built into `dash` is very robust, and this isn't an issue, but it's still mentioned here.

This does become a problem without quoting, though not quoting a `test` expression is always bad, regardless of the type of test.

### `export parameter="${parameter:-"default"}"`

This sets a variable, providing a default if it does not already have a value. For example:

```sh
set -eu

COLOR=blue

export COLOR="${COLOR:-"grey"}"
echo "${COLOR}"
# blue

NAME=

export NAME="${NAME:-"you"}"
echo "Hello, ${NAME}"
# Hello, you

PREFIX=

# Without the : only uses default if the parameter is truly unset
export PREFIX="${PREFIX-"--- "}"
echo "${PREFIX}message"
# message
```

[shell specification]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html>
[parameter expansion]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_06_02> "Parameter expansion in a recent edition of the standard"
[`$@` and `$*` examples]: <https://pubs.opengroup.org/onlinepubs/9699919799.2016edition/xrat/V4_xcu_chap02.html#tag_23_02_05_02>
[echo builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/echo.html>
[command builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/command.html>
[jq]: <https://stedolan.github.io/jq/>
[test builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/test.html>
[colon builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#colon>
[exec builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#exec>
[eval builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#eval>
[dot builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#dot>
[export builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#dot>
[read builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/read.html>
[set builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#set>
[unset builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#unset>
[trap builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#trap>
[printf builtin]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/printf.html>
[LXD]: <https://linuxcontainers.org/lxd/#what-is-lxd> "about the Linux Container Daemon"
[basename]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/basename.html>
[date]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/date.html>
[dirname]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/dirname.html>
[if statement]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_09_04_07>
[for loop]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_09_04_03>
[case statement]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_09_04_05>
[while loop]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_09_04_09>