# SOP — Conditional Access / MFA policy rollout procedure

> Lab/practice SOP against a fictitious `contoso.onmicrosoft.com` tenant
> with Entra ID Conditional Access and MFA. Not a real employer's
> procedure.

## Scope

A staged rollout procedure for introducing a new (or materially changed)
Conditional Access policy — e.g. requiring MFA for all cloud app access,
blocking legacy authentication, or requiring a compliant device — without
locking out a large population of users on day one.

## Why staged rollout matters here specifically

Conditional Access policies apply tenant-wide and evaluate on every sign-in.
A policy with an unintended scope or a missed exclusion can lock out an
entire department (or, in the worst case, all admins) simultaneously,
and — unlike most changes — the blast radius is authentication itself,
which can make it hard to even get back in to undo the change. Staging
and break-glass accounts exist specifically to prevent that failure mode.

## Prerequisites

- At least one **break-glass emergency access account**: cloud-only,
  excluded from all Conditional Access policies, long complex password
  stored per the org's secrets-management procedure (not in this repo —
  a lab stand-in only), monitored for any sign-in (a sign-in on a
  break-glass account should always trigger an alert, since it should
  essentially never be used).
- Global Administrator or Conditional Access Administrator role for
  making policy changes.
- A defined pilot group (security group in Entra ID) to scope the
  earliest rollout stage to a small, opt-in-aware population — typically
  the IT/helpdesk team itself first.

## Procedure

### 1. Confirm break-glass accounts are excluded and working

Before touching any policy, verify:

**Entra admin center** → **Protection** → **Conditional Access** →
**Policies** — for every existing and the new policy being drafted,
confirm the break-glass account(s) are listed under **Users** →
**Exclude**.

Test sign-in with the break-glass account from an unmanaged/incognito
session to confirm it currently works, before making any change that
could affect it.

### 2. Create the new policy in Report-only mode

**Conditional Access** → **New policy**. Configure the intended
conditions (users/groups, cloud apps, conditions) and grant controls
(e.g. **Require multifactor authentication**), but set
**Enable policy** to **Report-only** — this evaluates and logs what
*would* happen without actually enforcing it.

### 3. Review Report-only results before enforcing anything

Let it run for a representative period (a full business week minimum, to
capture different user patterns — e.g. users who only sign in from a
specific app periodically). Review under:

**Conditional Access** → select the policy → **Insights and reporting**,
or **Sign-in logs** filtered by **Conditional Access** → policy result.

Look specifically for:
- Any user who would have been **blocked** who shouldn't be (wrong scope,
  a legitimate service account caught by a "all users" condition, a
  legacy app that can't do MFA yet).
- Volume of users who would newly be prompted for MFA, to size the
  helpdesk impact and communication needed.

### 4. Fix scope issues found in report-only, re-verify

Common findings at this stage: a service/break-glass account caught
because "All users" was used instead of a scoped group with exclusions;
an on-prem legacy app relying on Basic Auth that legitimately can't
support MFA yet (handle via a scoped, time-boxed exclusion with a
tracked remediation date, not a permanent one).

### 5. Roll out to the pilot group first, enforced

Change **Users** scope to the pilot group only (IT/helpdesk), set
**Enable policy** to **On**. Have the pilot group actually use the
affected apps for a few days, watching for unexpected friction, before
expanding.

### 6. Communicate before wider rollout

Send advance notice to the next wave of affected users: what's changing,
what they'll see (an MFA prompt, a device compliance check, etc.), and
who to contact if they get unexpectedly blocked. Include the timing.

### 7. Expand in waves, not all at once

Move from pilot → one department → all users, over however many stages
match the org's risk tolerance and the population size. At each wave,
re-check the sign-in logs for unexpected blocks before proceeding to the
next.

### 8. Final full rollout — re-confirm break-glass exclusion one more time

Immediately before the final "all users" wave, re-verify break-glass
accounts are still excluded (a policy edit during the staged rollout can
sometimes reset a scope condition) and re-test break-glass sign-in.

## Rollback

If a wave causes unexpected lockouts:

1. Do **not** attempt to fix forward under pressure with users actively
   locked out — first set the policy back to **Report-only** or
   **Off**, which immediately stops enforcement tenant-wide/for the
   affected scope.
2. Use a break-glass account to regain admin access if the person making
   the fix is themselves locked out.
3. Investigate and fix the scope/condition issue with the policy
   disabled, re-test in Report-only, then resume the staged rollout from
   the last successful wave — don't skip back to full enforcement
   directly.

## Verification checklist

- [ ] Break-glass account(s) excluded and sign-in tested before *and*
      immediately before final rollout
- [ ] Policy ran in Report-only long enough to capture a representative
      sign-in pattern (minimum one business week)
- [ ] No unexpected blocks in Report-only logs, or all findings resolved
      with tracked, time-boxed exclusions
- [ ] Pilot group ran enforced for several days with no unresolved issues
- [ ] Each wave's sign-in logs reviewed before expanding to the next
- [ ] Helpdesk briefed on the rollout schedule and common
      "what do I do if a user gets blocked" responses
