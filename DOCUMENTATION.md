# Recreate Documentation

This document outlines how to use the Recreate library

> This documentation also contains a section on Relayer and how to use it within Roblox

# Contents

1. Recreate
	1. Introduction
	2. How to create objects
	3. Components
	4. Refs
	5. Effects with Roblox Signals
	6. Hydration
	7. Suppression
2. Relayer and Roblox
	1. Installation
	2. Creating Roblox objects
	3. Children
	4. Events and Change signals
	5. Tags
- Appendix A: Recreate Reference
- Appendix B: Relayer Reference

# Recreate

## 1. Introduction

Recreate is a library designed to be much simpler than other UI libraries in the Luau userspace, it trusts the user with virtual items rather than abstractions, which speed up code performance. I do not claim Recreate to be better than other options, just that is is another option, the xkcd image below demonstrates why we do not attempt to solve every single possible usecase.

[![xkcd standards](https://imgs.xkcd.com/comics/standards.png)](https://xkcd.com/927/)  
*xkcd 927 - standards*

Recreate instead works by connecting directly to a renderer, which defines environment specific logic, and the renderer itself tells Recreate what the `IVirtual` and `IDyna` types should be when `create` is called. More information on these will be introduced as they're used. Recreate itself is also stateless, which means returned objects can be used with no side effects (renderers may define some state).

## 2. How to create objects

Recreate offers two functions for creating objects, `create`, and `hydrate`. For this section, we will focus on the former since this creates new objects rather than modifying current ones.

The function takes a table called `props`, then returns the virtual item as defined by the renderer. For these examples, we'll assume we're using the Relayer renderer that targets the Roblox platform, however, the baseline syntax should be the same for any renderer.

```luau
local textLabel = Recreate.create {
	-- For Relayer, you define what properties the instance should
	-- be created with, as well as the ClassName of the instance

	ClassName = "TextLabel",
	Size = UDim2.fromOffset(200, 50),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Text = "Hello from Recreate+Relayer!",
	TextColor3 = Color3.new(0, 0, 0)
}

-- textLabel is an instance, so you can use it like one
textLabel.Parent = script.Parent
```

Children should be pure tables and do not nest `create` calls, the motivation for this approach will be explained when handling `Refs`

```luau
local frame = Recreate.create {
	ClassName = "Frame",
	AutomaticSize = Enum.AutomaticSize.XY,

	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),

	-- This key is renderer-specific, Relayer uses a Dyna
	[Relayer.Children] = {
		Padding = {
			ClassName = "UIPadding",
			PaddingTop = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4)
		},

		Label = {
			ClassName = "TextLabel",
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Text = "I'm inside a frame!",
			TextColor3 = Color3.new(0, 0, 0)
		}
	}
}
```

### Hydration Order

Hydration is completed in a well-defined order, which is given below

1. For each object,
	1. Bind `Hydrate` effect
	2. Resolve children
	3. Set props which are not considered reactive keys
2. Resolve refs
	* reactive keys are still defered
3. Bind reactive keys
4. Set `Hydrate` effects to true


## 3. Components

Components allow you make reusable templates that extend hydration. You can define any function that retuns a table, you can then directly inline into your trees by calling it.

```luau
return function(padding: UDim?)
	padding = padding or UDim.new()

	-- Do not use Recreate.create here as this gets inlined inside your props table
	return {
		ClassName = "UIPadding",
		PaddingTop = padding,
		PaddingLeft = padding,
		PaddingRight = padding,
		PaddingBottom = padding
	}
end
```

You can then simply call it as a child, or directly inside `create`

```luau
local frame = Recreate.create {
	ClassName = "Frame",
	AutomaticSize = Enum.AutomaticSize.XY,

	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),

	[Relayer.Children] = {
		-- Call the component directly
		Padding = paddingComponent(UDim.new(0, 4)),

		Label = {
			ClassName = "TextLabel",
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Text = "I'm inside a frame!",
			TextColor3 = Color3.new(0, 0, 0)
		}
	}
}
```

You can also chain components by simply returning more components directly, or as Children of the previous

```luau
return Recreate.component(...)
	return Component2(...)
end

return Recreate.component(...)
	return {
		ClassName = "Frame",

		[Relayer.Children] = {
			com1 = Component1(...),
			com2 = Component2(...)
		}
	}
end
```

## 4. Refs

Sometimes you may want to know info about a virtual object before its created, ie, a child of itself, this is why objects are resolved top-down, instead of bottom-up

```luau
-- technically this can be an empty table,
-- but given the key here for typing reasons
local ref = {value = nil::Instance?}

local frame = Recreate.create {
	[Recreate.Ref] = ref,

	ClassName = "Frame",
	AutomaticSize = Enum.AutomaticSize.XY,

	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),

	[Relayer.Children] = {
		-- Call the component directly
		Padding = paddingComponent(UDim.new(0, 4)),

		Label = {
			ClassName = "TextLabel",
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Text = Recreate.useRef(ref, function(refValue)
				-- the ref isn't resolved yet, so we need to use a
				-- callback to resolve it once its allocated
				return refValue.Name
			end)
			TextColor3 = Color3.new(0, 0, 0)
		}
	}
}
```

> The exact order in which useRef is resolved is undefined and should not be depended upon.

To prevent side effects, refs should only be allocated once. Refs are more useful in event-based code, so this example does not demonstrate their usecase fully. Children cannot be connected to `useRef`.

## 5. Effects with Roblox Signals

Recreate uses the `Roblox/Signals` library to provide reactive state, for information on how to use that library, click [here](https://github.com/Roblox/signals).

To use a Signal in Recreate, you can directly bind it as an effect to a hydration table using `useEffect`. This is done to discriminate between an effect a function the renderer may want to consume.

```luau
local get, set = Signals.createSignal(Lighting.TimeOfDay)

local textLabel = Recreate.create {
	-- For Relayer, you define what properties the instance should
	-- be created with, as well as the ClassName of the instance

	ClassName = "TextLabel",
	Size = UDim2.fromOffset(200, 50),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Text = Recreate.useEffect(time)
	TextColor3 = Color3.new(0, 0, 0)
}
```

You can also use `Recreate.setEffect` to bind an effect outside the hydration table, this allows to pass `getter<T>` directly instead of needing to wrap it.

```luau
Recreate.setEffect(game.Lighting, "ClockTime", getTimeNow)
```

You can return a `useEffect` from within `useRef` if the usecase suffices.

## 6. Hydration

Hydration works almost identically to `create`, except that it works on objects already created. This is useful if you want to bind something that cant otherwise be created directly, ie, for Roblox, a `DockWidgetPluginGui`

When Hydration is completed, any signals bound through `Recreate.Hydrated` will be set to true. The order of hydration, much like refs, is undefined.

## 7. Suppression

Sometimes, it's useful to render an object, but suppress its reactive logic, `Recreate.suppressed` exists to allow you to do this, you can define it anywhere in your tree to suppress that object and it's children. Suppression disables reactive keys and effects.

```luau
Recreate.create {
	ClassName = "Frame",

	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 100, 0, 50),
	
	[Recreate.renderer.Children] = {
		{
			[Recreate.suppressed] = true,
			ClassName = "TextButton",
			Text = "Hello world!",
			Size = UDim2.new(1, 0, 1, 0),
			
			[Recreate.renderer.Event "Activated"] = function()
				print("this should not print")
			end,
		},
		{
			ClassName = "TextButton",
			Text = "Hello world!",
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.new(0, 0, 1, 0),

			[Recreate.renderer.Event "Activated"] = function()
				print("this should print")
			end,
		},
	}
}
```

# 2. Relayer and Roblox

## 1. Installation

This package is hosted in two places, on the [Creator Store](https://create.roblox.com/store/asset/97554899505380/Recreate), and on [GitHub](https://github.com/metatablecat/Recreate/releases), these are stable releases which are determined to be ready for release. You can alternatively build the model file yourself using Rojo if you want the latest build, be aware, this will likely contain bugs.

The package is provided as a ModuleScript with the rendering and signal components stored inside the package. Relayer is stored as `Recreate.renderer`.

You can load it with `require` in Studio. Its a good idea to put this module in `ReplicatedStorage`, since its commonly used for UI.

## 2. Creating Roblox Objects

This has been explained in detail in Recreate since this documentation targets Relayer.

## 3. Children

Children are assigned with the `Relayer.Children` `Dyna`, you pass a direct table with `name=props` pairs for each child instance.

```luau
local frame = Recreate.create {
	ClassName = "Frame",
	AutomaticSize = Enum.AutomaticSize.XY,

	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),

	[Relayer.Children] = {
		Label = {
			ClassName = "TextLabel",
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Text = "I'm inside a frame!",
			TextColor3 = Color3.new(0, 0, 0)
		}
	}
}
```

You can also manipulate Children with a table using the `setValue` function on Recreate.

```luau
Recreate.setValue(frame, Relayer.Children, {
	inst1, inst2
})
```

This operation removes (sets Parent to `nil`, but does not destroy) any instances which may already be part of the Instance and replaces them with the ones provided in the table.

## 4. Events and Change signals

Events and change signals are controlled using the `EventDyna` and `ChangeDyna` respectively, these are constructors which describe *what* you want to connect to.

For events, this will be an event name defined on the `Instance`, while for changing properties, it can be any property name.

```luau
local textbox = Recreate.create {
	ClassName = "TextBox",
	AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Color3.new(0, 0, 0),
	
	[Relayer.Change "Text"] = function(sp, prop, newValue)

	end

	[Relayer.Event "FocusLost"] = function(sp, io, enterPressed)

	end
}
```

You can control if an event is bound this way by using `setValue`, and a `Dyna` with the same parameters, setting it to `nil` or another function will disconnect the existing event.

## 5. Tags

Tags are useful for StyleSheets, they are controlled similarly to children using `Relayer.Tags`, but should just be a table of StyleRules to bind against the instance.

```luau
local frame = Recreate.create {
	[Relayer.Tags] = {
		".main-content"
	}

	ClassName = "Frame",
	AutomaticSize = Enum.AutomaticSize.XY,

	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.new(1, 1, 1),

	[Relayer.Children] = {
		Label = {
			ClassName = "TextLabel",
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Text = "I'm inside a frame!",
			TextColor3 = Color3.new(0, 0, 0)
		}
	}
}
```