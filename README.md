# Recreate

This is rewritten from the ground up and will likely have issues, help us fix it!

Recreate is my internal UI framework that I’ve been using in many forms since 2023, it started as a descendant of `RbxUtility.Create`, but expanded to include several framework features. I wrote my own framework as I found the two major options at the time to have issues that made them unusable.

# Motivation

Several UI frameworks already exist, but I found issues with the two major options, Roact (this started development before react-lua) and Fusion

Roact performed horribly on Roblox and used a lot of JS semantics which dont work nicely in Lua, its also not that useful without JSX, however, I did find the virtual tree approach to be quite useful, given how messy Roblox instances can be.

Fusion had a syntax I liked but its codebase is very unstable and appears to change between versions, its also a very bloated library which has a lot of features most people wont ever use.

Recreate takes concepts from both libraries and packages it into a bundle thats more approachable and how I'd like. I do not claim to say Recreate is better than either of these libraries however, so you can use whatever you like.

# Example Usage

The following sample renders a simple `TextLabel`

```lua
local Recreate = require(script.Parent.Recreate.Recreate)
local Relayer = require(script.Parent.Recreate.Relayer)

local n = Recreate.create {
	[Relayer.ClassName] = "TextLabel",

	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(200, 50),
	Position = UDim2.fromScale(0.5, 0.5)
	Text = "Hello from Recreate+Relayer!"
}

Relayer.mount(n)
```

You may notice both a Recreate and Relayer library, this is because rendering is seperate from the main library, this only scratches the top of Recreate's features.
