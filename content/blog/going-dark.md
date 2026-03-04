---
title: "Dark mode on all the things"
date: 2018-12-24T13:21:37+11:00
---

# Arc Dark

![Arc Dark preview](https://camo.githubusercontent.com/e343c19dc3e67b13908733bf26ecfdfc1405749a/687474703a2f2f692e696d6775722e636f6d2f3541476c436e412e706e67)

`sudo dnf install arc-theme gnome-tweaks`

## nvim

![catppuccin/nvim preview](/going_dark_nvim.png)

```lua
  {
    "catppuccin/nvim", -- https://github.com/catppuccin/nvim
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      dim_inactive = {
        enabled = true,    -- dims the background color of inactive window
        -- shade = "dark",
        percentage = 0.99, -- 50, -- 0.15, -- percentage of the shade to apply to the inactive window
      },
      integrations = {
        notify = true,
        notifier = true,
        lsp_trouble = true,
        barbar = true,
        neotree = true,
        noice = true,
        dropbar = { enabled = true },
        mason = true,
        nvim_surround = true,
        overseer = true,
        which_key = true,
        snacks = {
          enabled = true,
          -- indent_scope_color = "", -- catppuccin color (eg. `lavender`) Default: text
        },
        native_lsp = {
          enabled = true,
          virtual_text = {
            errors = { "italic" },
            hints = { "italic" },
            warnings = { "italic" },
            information = { "italic" },
            ok = { "italic" },
          },
          underlines = {
            errors = { "underline" },
            hints = { "underline" },
            warnings = { "underline" },
            information = { "underline" },
            ok = { "underline" },
          },
          inlay_hints = {
            background = true,
          },
        },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin-macchiato")
    end
  },

```

# Everything Else - Dark Reader

https://darkreader.org/
