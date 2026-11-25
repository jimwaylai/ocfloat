# opencode Floating

A macOS desktop app that summons a floating chat window via a system-wide hotkey, letting the user ask quick general-purpose questions answered through opencode.

## Language

**Quick Chat**:
The floating window summoned by the global hotkey, used for fast general-purpose Q&A (not project-aware coding work).
_Avoid_: Popup, overlay, spotlight

**Scratch Workspace**:
The fixed, neutral directory that all Quick Chat conversations run in, so they are never tied to a user's code project.
_Avoid_: Project, working directory

**Conversation**:
One continuous thread of questions and answers in the Quick Chat, backed by a single opencode session.
_Avoid_: Chat, thread, session (session is opencode's term for the backing record)

**Answer**:
Everything the Quick Agent produces in response to one question — text, reasoning and web lookups — until it stops; one Answer may span several opencode assistant messages.
_Avoid_: Reply, response, assistant message

**Idle Reset**:
The rule, evaluated only at the moment of a Summon, that starts a new Conversation when more than N minutes have passed since the Last Interaction and there is no Unread Answer.
_Avoid_: Timeout, expiry

**Summon**:
Bringing the Quick Chat to the front via the global hotkey. Summoning and hiding are not interactions.
_Avoid_: Open, launch, invoke

**Last Interaction**:
The later of the last message sent and the last answer completed in the current Conversation.
_Avoid_: Last activity, last used

**Unread Answer**:
An answer that finished while the Quick Chat was hidden and has not yet been seen; it always blocks Idle Reset.
_Avoid_: New message, notification

**Draft**:
Unsent text in the input box; it belongs to the Quick Chat, not to any Conversation, and survives Idle Reset.
_Avoid_: Pending message

**Recent Conversations**:
A short list of the latest Conversations in the Scratch Workspace, from which one can be resumed.
_Avoid_: History, sidebar, archive

**Quick Agent**:
The dedicated, hidden, user-global opencode agent every Conversation uses: tuned for short direct answers, allowed only web lookup tools, never asks for permission.
_Avoid_: Assistant, bot, default agent

**Preferred Model**:
The model (and variant) most recently chosen by the user; every new Conversation starts with it.
_Avoid_: Default model, current model
