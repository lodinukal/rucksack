#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <git2.h>

#define UNUSED(x) (void)(x)

static int readline(char **out)
{
    int c, error = 0, length = 0, allocated = 0;
    char *line = NULL;

    errno = 0;

    while ((c = getchar()) != EOF)
    {
        if (length == allocated)
        {
            allocated += 16;

            if ((line = realloc(line, allocated)) == NULL)
            {
                error = -1;
                goto error;
            }
        }

        if (c == '\n')
            break;

        line[length++] = c;
    }

    if (errno != 0)
    {
        error = -1;
        goto error;
    }

    line[length] = '\0';
    *out = line;
    line = NULL;
    error = length;
error:
    free(line);
    return error;
}

static int ask(char **out, const char *prompt, char optional)
{
    printf("%s ", prompt);
    fflush(stdout);

    if (!readline(out) && !optional)
    {
        fprintf(stderr, "Could not read response: %s", strerror(errno));
        return -1;
    }

    return 0;
}

int cred_acquire_cb(git_credential **out,
                    const char *url,
                    const char *username_from_url,
                    unsigned int allowed_types,
                    void *payload)
{
    char *username = NULL, *password = NULL, *privkey = NULL, *pubkey = NULL;
    int error = 1;

    UNUSED(url);
    UNUSED(payload);

    if (username_from_url)
    {
        if ((username = strdup(username_from_url)) == NULL)
            goto out;
    }
    else if ((error = ask(&username, "Username:", 0)) < 0)
    {
        goto out;
    }

    if (allowed_types & GIT_CREDENTIAL_SSH_KEY)
    {
        int n;

        if ((error = ask(&privkey, "SSH Key:", 0)) < 0 ||
            (error = ask(&password, "Password:", 1)) < 0)
            goto out;

        if ((n = snprintf(NULL, 0, "%s.pub", privkey)) < 0 ||
            (pubkey = malloc(n + 1)) == NULL ||
            (n = snprintf(pubkey, n + 1, "%s.pub", privkey)) < 0)
            goto out;

        error = git_credential_ssh_key_new(out, username, pubkey, privkey, password);
    }
    else if (allowed_types & GIT_CREDENTIAL_USERPASS_PLAINTEXT)
    {
        if ((error = ask(&password, "Password:", 1)) < 0)
            goto out;

        error = git_credential_userpass_plaintext_new(out, username, password);
    }
    else if (allowed_types & GIT_CREDENTIAL_USERNAME)
    {
        error = git_credential_username_new(out, username);
    }

out:
    free(username);
    free(password);
    free(privkey);
    free(pubkey);
    return error;
}