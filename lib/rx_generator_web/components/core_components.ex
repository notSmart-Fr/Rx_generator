defmodule RxGeneratorWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: RxGeneratorWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          aria-invalid={@errors != []}
          aria-describedby={@errors != [] && "#{@id}-error"}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <div :if={@errors != []} id={"#{@id}-error"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          aria-invalid={@errors != []}
          aria-describedby={@errors != [] && "#{@id}-error"}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <div :if={@errors != []} id={"#{@id}-error"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          aria-invalid={@errors != []}
          aria-describedby={@errors != [] && "#{@id}-error"}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <div :if={@errors != []} id={"#{@id}-error"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"
  attr :rest, :global

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} aria-hidden={!Map.has_key?(@rest, :"aria-label")} {@rest} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(RxGeneratorWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(RxGeneratorWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders the keyboard-driven prescription omnibar.
  """
  attr :id, :string, default: "prescription-omnibar"
  attr :query, :string, default: ""
  attr :error, :string, default: nil
  attr :candidates, :list, default: []
  attr :highlighted_index, :integer, default: 0

  def omnibar(assigns) do
    ~H"""
    <div class="relative w-full">
      <form id="omnibar-form" phx-submit="commit_omnibar" novalidate class="relative">
        <div class={[
          "flex h-11 items-center rounded-[3px] border bg-white px-3 transition-colors",
          @error && "border-amber-500 ring-1 ring-amber-300",
          !@error &&
            "border-neutral-300 focus-within:border-[#0F4C5C] focus-within:ring-1 focus-within:ring-[#0F4C5C]"
        ]}>
          <.icon name="hero-magnifying-glass" class="mr-2.5 h-5 w-5 text-neutral-400" />
          <input
            id={@id}
            name="query"
            type="text"
            value={@query}
            autofocus
            autocomplete="off"
            aria-label="Search the DGDA drug catalog"
            aria-expanded={@candidates != []}
            aria-controls="omnibar-dropdown"
            placeholder="Search DGDA drug catalog — brand or generic (e.g. Napa, Ciprocin 500)"
            phx-keyup="parse_and_suggest"
            phx-debounce="50"
            phx-hook="Omnibar"
            class="w-full border-0 bg-transparent p-0 text-base text-neutral-950 placeholder:text-neutral-400 focus:outline-none focus:ring-0"
          />
          <kbd class="hidden shrink-0 rounded-[3px] border border-neutral-200 bg-neutral-50 px-1.5 py-0.5 text-[11px] font-medium text-neutral-500 sm:inline-block">
            Enter
          </kbd>
        </div>
      </form>

      <%= if @candidates != [] do %>
        <div
          id="omnibar-dropdown"
          aria-live="polite"
          class="absolute inset-x-0 top-full z-40 mt-1 overflow-hidden rounded-[3px] border border-neutral-200 bg-white divide-y divide-neutral-200"
        >
          <button
            :for={{candidate, idx} <- Enum.with_index(@candidates)}
            type="button"
            id={"candidate-#{idx}"}
            onmousedown="event.preventDefault()"
            phx-click="select_candidate"
            phx-value-index={idx}
            class={[
              "flex w-full min-h-11 items-center justify-between gap-3 px-3 py-2 text-left transition-colors",
              idx == @highlighted_index && "bg-zinc-100",
              idx != @highlighted_index && "hover:bg-neutral-50"
            ]}
          >
            <div class="min-w-0">
              <span class="text-sm font-black uppercase tracking-wide text-neutral-950">
                {String.upcase(candidate.generic_name)}
              </span>
              <span class="ml-2 text-[11px] text-neutral-500">{candidate.brand_name}</span>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <span class="rounded-[3px] border border-neutral-200 bg-neutral-50 px-1.5 py-0.5 font-mono text-[11px] text-neutral-600">
                {candidate.dosage_form} · {candidate.strength}
              </span>
              <%= if idx == @highlighted_index do %>
                <span class="hidden text-[10px] font-semibold uppercase tracking-wide text-neutral-400 sm:inline">
                  Add
                </span>
              <% end %>
            </div>
          </button>

          <div class="flex items-center justify-between bg-neutral-50 px-3 py-1.5 text-[11px] text-neutral-500">
            <span>↑↓ navigate · Enter or click to add · Esc to dismiss</span>
            <span>Local DGDA snapshot</span>
          </div>
        </div>
      <% end %>

      <%= if @error do %>
        <div class="mt-2 flex items-center gap-1.5 text-sm font-medium text-amber-700" role="status">
          <.icon name="hero-exclamation-triangle" class="h-4 w-4 shrink-0" />
          {@error}
        </div>
      <% end %>
    </div>
    """
  end

  attr :active, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  defp sig_chip(assigns) do
    ~H"""
    <button
      type="button"
      aria-pressed={to_string(@active)}
      class={[
        "min-h-7 rounded-[3px] border px-2 text-[11px] leading-none transition-colors focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[#0F4C5C]",
        @active && "border-[#0F4C5C] bg-[#0F4C5C] text-white",
        !@active &&
          "border-neutral-300 bg-white text-neutral-700 hover:border-neutral-500 hover:text-neutral-950"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp value_options(current, presets) when is_binary(current) and current != "" do
    if current in presets, do: presets, else: [current | presets]
  end

  defp value_options(_current, presets), do: presets

  defp pair_options(current, presets) when is_binary(current) and current != "" do
    if Enum.any?(presets, &(elem(&1, 0) == current)),
      do: presets,
      else: [{current, current} | presets]
  end

  defp pair_options(_current, presets), do: presets

  defp advice_active?(advice, chip) do
    chip in String.split(advice || "", "\n", trim: true)
  end

  @doc """
  Renders the interactive prescription editor.

  This pane is a control panel, not a document: it holds patient inputs,
  clinical notes, medication cards, and advice controls. The printable
  document is rendered by `a4_paper_preview/1`.
  """
  attr :id, :string, default: "prescription-canvas"
  attr :items, :list, default: []
  attr :clinical_warnings, :list, default: []
  attr :state, :atom, default: :draft
  attr :draft, :map, default: nil

  def prescription_editor(assigns) do
    {clinical_findings, general_advice} =
      RxGenerator.Prescriptions.SmartDefaults.split_clinical_notes_and_advice(
        assigns[:draft] && assigns[:draft].clinical_notes
      )

    assigns =
      assigns
      |> assign(:clinical_findings, clinical_findings)
      |> assign(:general_advice, general_advice)

    ~H"""
    <div id={@id} class="overflow-hidden rounded-[3px] border border-neutral-200 bg-white">
      <!-- Patient inputs -->
      <div id="patient-vault-fields" class="border-b border-neutral-200 px-4 py-3">
        <div class="mb-2 flex items-center justify-between">
          <span class="text-xs font-semibold text-neutral-800">Patient</span>
          <span class="text-[10px] text-neutral-500">Stored encrypted on this device</span>
        </div>

        <%= if @state != :locked do %>
          <form id="patient-vault-form" phx-change="update_patient_vault" novalidate>
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div>
                <label for="patient-name" class="mb-1 block text-[11px] font-medium text-neutral-600">
                  Name
                </label>
                <input
                  id="patient-name"
                  type="text"
                  name="patient_name"
                  value={(@draft && @draft.patient_name) || ""}
                  placeholder="e.g. Rahim Uddin"
                  phx-debounce="300"
                  class="min-h-9 w-full rounded-[3px] border border-neutral-300 bg-white px-2.5 text-sm text-neutral-950 placeholder:text-neutral-400 focus:border-[#0F4C5C] focus:outline-none focus:ring-1 focus:ring-[#0F4C5C]"
                />
              </div>
              <div>
                <label for="patient-phone" class="mb-1 block text-[11px] font-medium text-neutral-600">
                  Phone
                </label>
                <input
                  id="patient-phone"
                  type="text"
                  name="patient_phone"
                  value={(@draft && @draft.patient_phone) || ""}
                  placeholder="e.g. +880 1712-345678"
                  phx-debounce="300"
                  class="min-h-9 w-full rounded-[3px] border border-neutral-300 bg-white px-2.5 font-mono text-sm text-neutral-950 placeholder:text-neutral-400 focus:border-[#0F4C5C] focus:outline-none focus:ring-1 focus:ring-[#0F4C5C]"
                />
              </div>
              <div>
                <label for="patient-age" class="mb-1 block text-[11px] font-medium text-neutral-600">
                  Age / Sex
                </label>
                <input
                  id="patient-age"
                  type="text"
                  name="patient_age"
                  value={(@draft && @draft.patient_age) || ""}
                  placeholder="e.g. 48Y / Male"
                  phx-debounce="300"
                  class="min-h-9 w-full rounded-[3px] border border-neutral-300 bg-white px-2.5 text-sm text-neutral-950 placeholder:text-neutral-400 focus:border-[#0F4C5C] focus:outline-none focus:ring-1 focus:ring-[#0F4C5C]"
                />
              </div>
            </div>
          </form>
        <% else %>
          <div class="flex flex-wrap gap-x-6 gap-y-1 text-sm text-neutral-900">
            <span><span class="text-neutral-500">Name:</span> {(@draft && @draft.patient_name) || "—"}</span>
            <span><span class="text-neutral-500">Age/Sex:</span> {(@draft && @draft.patient_age) ||
              "—"}</span>
            <span :if={@draft && @draft.patient_phone} class="font-mono">
              <span class="text-neutral-500">Phone:</span> {@draft.patient_phone}
            </span>
          </div>
        <% end %>
      </div>

      <%= if @clinical_warnings != [] do %>
        <div
          id="clinical-warnings-banner"
          role="status"
          aria-live="polite"
          class="mb-5 space-y-2 print:hidden"
        >
          <div
            :for={warning <- @clinical_warnings}
            class={[
              "flex items-start gap-2 px-3.5 py-2.5 rounded-[3px] border text-xs font-medium",
              warning.kind == :duplicate_generic &&
                "bg-amber-50 border-amber-300 text-amber-900",
              warning.kind == :controlled_substance &&
                "bg-rose-50 border-rose-300 text-rose-900"
            ]}
          >
            <.icon name="hero-exclamation-triangle" class="w-4 h-4 shrink-0 mt-0.5" />
            <span>{warning.message}</span>
          </div>
        </div>
      <% end %>

      <!-- Clinical notes + medications -->
      <div class="grid grid-cols-1 md:grid-cols-12">
        <!-- 1/3 left: optional clinical notes -->
        <div
          id="clinical-left-margin"
          class="space-y-2 border-b border-neutral-200 px-4 py-4 md:col-span-4 md:border-b-0 md:border-r"
        >
          <%= if @state != :locked do %>
            <div class="flex items-center justify-between">
              <label for="clinical-notes" class="text-xs font-semibold text-neutral-800">
                Clinical notes
              </label>
              <span class="text-[10px] text-neutral-500">Optional</span>
            </div>
            <div class="flex flex-wrap gap-1">
              <button
                :for={prefix <- RxGenerator.Prescriptions.SmartDefaults.clinical_prefixes()}
                type="button"
                phx-click="append_clinical_prefix"
                phx-value-prefix={prefix}
                class="min-h-8 rounded-[3px] border border-neutral-300 bg-white px-2 font-mono text-[11px] font-medium text-neutral-700 hover:border-[#0F4C5C] hover:text-[#0F4C5C] focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[#0F4C5C]"
              >
                +{prefix}
              </button>
            </div>
            <textarea
              id="clinical-notes"
              name="clinical_notes"
              form="patient-vault-form"
              rows="10"
              phx-debounce="300"
              placeholder="C/C: &#10;O/E: &#10;Dx: "
              class="min-h-[220px] w-full rounded-[3px] border border-neutral-300 bg-white px-2.5 py-2 font-mono text-sm text-neutral-950 placeholder:text-neutral-400 focus:border-[#0F4C5C] focus:outline-none focus:ring-1 focus:ring-[#0F4C5C]"
            >{@clinical_findings}</textarea>
            <p class="text-[11px] leading-snug text-neutral-500">
              Leave blank to keep this margin free for handwriting on the printed sheet.
            </p>
          <% else %>
            <%= if String.trim(@clinical_findings || "") != "" do %>
              <div class="whitespace-pre-line text-sm leading-relaxed text-neutral-950">
                {@clinical_findings}
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- 2/3 right: medications -->
        <div id="clinical-right-rx-column" class="px-4 py-4 md:col-span-8">
          <div class="mb-3 flex items-baseline justify-between">
            <span class="text-sm font-semibold text-neutral-950">Medications</span>
            <span class="font-mono text-xs text-neutral-500">{length(@items)}</span>
          </div>

          <%= if @items == [] do %>
            <div class="rounded-[3px] border border-dashed border-neutral-300 px-4 py-10 text-center">
              <p class="text-sm font-medium text-neutral-700">No medications yet</p>
              <p class="mt-1 text-xs text-neutral-500">
                Type in the omnibar above, e.g. <span class="font-mono text-neutral-700">napa 1+0+1 5d pc</span>.
              </p>
            </div>
          <% else %>
            <ol class="space-y-2">
              <li
                :for={{item, index} <- Enum.with_index(@items)}
                id={"rx-item-#{index}"}
                class="rx-item-row rounded-[3px] border border-neutral-200 bg-white"
              >
                <div class="flex items-start justify-between gap-3 px-3 py-2.5">
                  <div class="min-w-0">
                    <div class="flex flex-wrap items-baseline gap-x-2">
                      <span class="font-mono text-xs text-neutral-500">{index + 1}.</span>
                      <span class="generic-name-print text-sm font-black uppercase tracking-wide text-neutral-950">
                        {String.upcase(item.generic_name_snapshot)}
                      </span>
                      <span class="brand-name-print text-sm text-neutral-700">
                        ({item.brand_name_snapshot})
                      </span>
                      <span class="font-mono text-[11px] text-neutral-500">
                        {item.dosage_form_snapshot} &middot; {item.strength_snapshot}
                      </span>
                      <span
                        :if={item.is_controlled_snapshot}
                        class="rounded-[2px] border border-rose-300 bg-rose-50 px-1.5 text-[10px] font-semibold uppercase tracking-wide text-rose-800"
                      >
                        Controlled
                      </span>
                    </div>
                    <p class="mt-1 text-sm leading-snug text-neutral-950">
                      {item.canonical_bengali_text ||
                        "#{item.dosage_matrix} — #{item.duration_expression}"}
                    </p>
                    <p :if={item.bengali_breakdown_text} class="text-[11px] text-neutral-500">
                      {item.bengali_breakdown_text}
                    </p>
                  </div>
                  <button
                    :if={@state != :locked}
                    type="button"
                    id={"remove-item-#{index}"}
                    phx-click="remove_prescription_item"
                    phx-value-item_id={item.id}
                    aria-label={"Remove #{item.brand_name_snapshot}"}
                    class="-mr-1 flex size-9 shrink-0 items-center justify-center rounded-[3px] text-neutral-400 hover:bg-neutral-100 hover:text-rose-700 focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-[#0F4C5C]"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>

                <%= if @state != :locked do %>
                  <% {active_timing, active_note} =
                    RxGenerator.Prescriptions.SmartDefaults.split_timing_and_note(
                      item.timing_instruction
                    ) %>
                  <div class="space-y-1.5 border-t border-neutral-200 px-3 py-2.5">
                    <div class="flex flex-wrap items-center gap-1">
                      <span class="w-16 shrink-0 text-[11px] font-medium text-neutral-500">
                        Dose
                      </span>
                      <.sig_chip
                        :for={
                          dose <-
                            value_options(
                              item.dosage_matrix,
                              RxGenerator.Prescriptions.SmartDefaults.dose_presets()
                            )
                        }
                        active={item.dosage_matrix == dose}
                        phx-click="update_item_sig"
                        phx-value-item_id={item.id}
                        phx-value-dosage_matrix={dose}
                        class="font-mono"
                      >
                        {dose}
                      </.sig_chip>
                    </div>

                    <div class="flex flex-wrap items-center gap-1">
                      <span class="w-16 shrink-0 text-[11px] font-medium text-neutral-500">
                        Timing
                      </span>
                      <.sig_chip
                        :for={
                          {code, label} <-
                            pair_options(
                              active_timing,
                              RxGenerator.Prescriptions.SmartDefaults.timing_presets()
                            )
                        }
                        active={active_timing == code}
                        phx-click="update_item_sig"
                        phx-value-item_id={item.id}
                        phx-value-timing_code={code}
                      >
                        {label}
                      </.sig_chip>
                    </div>

                    <div class="flex flex-wrap items-center gap-1">
                      <span class="w-16 shrink-0 text-[11px] font-medium text-neutral-500">
                        Duration
                      </span>
                      <.sig_chip
                        :for={
                          {dur_val, dur_label} <-
                            pair_options(
                              item.duration_expression,
                              RxGenerator.Prescriptions.SmartDefaults.duration_presets()
                            )
                        }
                        active={item.duration_expression == dur_val}
                        phx-click="update_item_sig"
                        phx-value-item_id={item.id}
                        phx-value-duration_expression={dur_val}
                        class="font-mono"
                      >
                        {dur_label}
                      </.sig_chip>
                    </div>

                    <form
                      id={"item-note-form-#{index}"}
                      phx-change="update_item_sig"
                      phx-submit="update_item_sig"
                      novalidate
                      class="flex items-center gap-2 pt-0.5"
                    >
                      <input type="hidden" name="item_id" value={item.id} />
                      <label for={"item-note-#{index}"} class="sr-only">
                        Note for {item.brand_name_snapshot}
                      </label>
                      <input
                        id={"item-note-#{index}"}
                        type="text"
                        name="custom_note"
                        value={active_note}
                        phx-debounce="300"
                        placeholder="Note — e.g. with warm water"
                        class="min-h-8 w-full rounded-[3px] border border-neutral-300 bg-white px-2 text-sm text-neutral-950 placeholder:text-neutral-400 focus:border-[#0F4C5C] focus:outline-none focus:ring-1 focus:ring-[#0F4C5C]"
                      />
                    </form>
                  </div>
                <% end %>
              </li>
            </ol>
          <% end %>

          <!-- General advice -->
          <div id="general-advice-section" class="mt-4 border-t border-neutral-200 pt-3">
            <div class="mb-1.5 flex items-baseline justify-between">
              <label for="general-advice" class="text-xs font-semibold text-neutral-800">
                Advice
              </label>
              <span class="text-[10px] text-neutral-500">পরামর্শ</span>
            </div>
            <%= if @state != :locked do %>
              <div class="mb-2 flex flex-wrap gap-1">
                <.sig_chip
                  :for={chip <- RxGenerator.Prescriptions.SmartDefaults.advice_chips()}
                  active={advice_active?(@general_advice, chip)}
                  phx-click="toggle_advice_chip"
                  phx-value-advice={chip}
                >
                  {chip}
                </.sig_chip>
              </div>
              <textarea
                id="general-advice"
                name="general_advice"
                form="patient-vault-form"
                rows="2"
                phx-debounce="300"
                placeholder="Or type custom advice…"
                class="min-h-16 w-full rounded-[3px] border border-neutral-300 bg-white px-2.5 py-1.5 text-sm text-neutral-950 placeholder:text-neutral-400 focus:border-[#0F4C5C] focus:outline-none focus:ring-1 focus:ring-[#0F4C5C]"
              >{@general_advice}</textarea>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the printed A4 prescription sheet.
  """
  attr :id, :string, default: "a4-paper-preview"
  attr :items, :list, default: []
  attr :state, :atom, default: :draft
  attr :rx_number, :string, default: nil
  attr :prescriber, :map, default: nil
  attr :active_chamber, :map, default: nil
  attr :draft, :map, default: nil
  attr :qr_svg, :string, default: nil

  def a4_paper_preview(assigns) do
    doctor_name =
      (assigns[:prescriber] && assigns[:prescriber].name) ||
        (assigns[:draft] && assigns[:draft].prescriber_name)

    bmdc_no =
      (assigns[:prescriber] && assigns[:prescriber].bmdc_no) ||
        (assigns[:draft] && assigns[:draft].prescriber_bmdc_no)

    qualifications =
      (assigns[:prescriber] && assigns[:prescriber].qualifications) ||
        (assigns[:draft] && assigns[:draft].prescriber_qualifications)

    specialty = assigns[:prescriber] && assigns[:prescriber].specialty

    ch_name =
      (assigns[:active_chamber] && assigns[:active_chamber].chamber_name) ||
        (assigns[:draft] && assigns[:draft].chamber_name)

    ch_address =
      (assigns[:active_chamber] && assigns[:active_chamber].address) ||
        (assigns[:draft] && assigns[:draft].chamber_address)

    ch_schedule =
      (assigns[:active_chamber] && assigns[:active_chamber].visiting_hours) ||
        (assigns[:draft] && assigns[:draft].chamber_schedule)

    ch_phone =
      (assigns[:active_chamber] && assigns[:active_chamber].contact_phone) ||
        (assigns[:draft] && assigns[:draft].chamber_phone)

    {clinical_findings, general_advice} =
      RxGenerator.Prescriptions.SmartDefaults.split_clinical_notes_and_advice(
        assigns[:draft] && assigns[:draft].clinical_notes
      )

    rx_date =
      case assigns[:draft] && assigns[:draft].finalized_at do
        %DateTime{} = dt -> Calendar.strftime(dt, "%d %b %Y")
        %NaiveDateTime{} = dt -> Calendar.strftime(dt, "%d %b %Y")
        _ -> Calendar.strftime(Date.utc_today(), "%d %b %Y")
      end

    assigns =
      assigns
      |> assign(:doctor_name, doctor_name)
      |> assign(:bmdc_no, bmdc_no)
      |> assign(:qualifications, qualifications)
      |> assign(:specialty, specialty)
      |> assign(:ch_name, ch_name)
      |> assign(:ch_address, ch_address)
      |> assign(:ch_schedule, ch_schedule)
      |> assign(:ch_phone, ch_phone)
      |> assign(:clinical_findings, clinical_findings)
      |> assign(:general_advice, general_advice)
      |> assign(:rx_date, rx_date)

    ~H"""
    <section
      id={@id}
      aria-label="Prescription sheet"
      phx-hook="PrintPrescription"
      class="a4-sheet mx-auto flex min-h-[297mm] w-full max-w-[210mm] flex-col border border-neutral-200 bg-white p-[12mm] text-neutral-950 print:m-0 print:w-auto print:max-w-none print:border-0"
    >
      <!-- Letterhead -->
      <header
        id="prescription-header-banner"
        class="print-two-col-header flex items-start justify-between gap-6 border-b-2 border-neutral-900 pb-3"
      >
        <div class="min-w-0">
          <p id="canvas-prescriber-name" class="text-lg font-bold leading-tight">
            {@doctor_name || "Prescriber not configured"}
          </p>
          <p id="canvas-prescriber-qualifications" class="mt-0.5 text-[12px] text-neutral-700">
            {@qualifications || "Add qualifications in Settings"}
            <span :if={@specialty}>
              &middot; {@specialty}
            </span>
          </p>
          <p :if={@doctor_name && @bmdc_no} class="mt-0.5 font-mono text-[11px] text-neutral-700">
            BM&amp;DC: <span id="canvas-prescriber-bmdc">{@bmdc_no}</span>
          </p>
        </div>
        <div class="max-w-[46%] shrink-0 text-right">
          <%= if @ch_name do %>
            <p id="canvas-chamber-name" class="text-[13px] font-semibold">{@ch_name}</p>
            <p id="canvas-chamber-address" class="text-[11px] leading-snug text-neutral-600">
              {@ch_address}
            </p>
            <p :if={@ch_schedule} id="canvas-chamber-schedule" class="text-[11px] text-neutral-600">
              {@ch_schedule}
            </p>
            <p
              :if={@ch_phone}
              id="canvas-chamber-phone"
              class="font-mono text-[11px] text-neutral-600"
            >
              {@ch_phone}
            </p>
          <% else %>
            <p class="text-[11px] italic text-neutral-500">Select a chamber above</p>
          <% end %>
        </div>
      </header>

      <!-- Patient line -->
      <div class="mt-3 flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1 border-b border-neutral-300 pb-2 text-[12px]">
        <span>
          <span class="text-neutral-500">Patient</span>
          <span class="font-semibold">{(@draft && @draft.patient_name) || "Walk-in"}</span>
        </span>
        <span :if={@draft && @draft.patient_age}>
          <span class="text-neutral-500">Age/Sex</span> {@draft.patient_age}
        </span>
        <span :if={@draft && @draft.patient_phone} class="font-mono">
          <span class="text-neutral-500">Phone</span> {@draft.patient_phone}
        </span>
        <span><span class="text-neutral-500">Date</span> {@rx_date}</span>
        <span class="font-mono">
          <span class="text-neutral-500">Rx</span> {@rx_number || "Unnumbered draft"}
        </span>
      </div>

      <!-- Clinical margin + Rx column -->
      <div class="mt-4 grid flex-1 grid-cols-12 gap-4">
        <div
          id="preview-left-margin"
          class="col-span-4 border-r border-neutral-300 pr-3 text-[11.5px] leading-relaxed"
        >
          <p class="mb-1 text-[10px] font-semibold text-neutral-400">Clinical notes</p>
          <%= if String.trim(@clinical_findings || "") != "" do %>
            <div class="whitespace-pre-line">{@clinical_findings}</div>
          <% end %>
        </div>

        <div id="preview-right-rx-column" class="col-span-8 flex flex-col">
          <p class="font-serif text-xl leading-none">&#8478;</p>
          <ol class="mt-2 space-y-3">
            <li :for={{item, idx} <- Enum.with_index(@items)} class="rx-item-row">
              <div class="flex flex-wrap items-baseline gap-x-1.5 text-[12px]">
                <span class="font-mono text-neutral-500">{idx + 1}.</span>
                <span class="generic-name-print text-[12.5px] font-black uppercase tracking-wide text-neutral-950">
                  {String.upcase(item.generic_name_snapshot)}
                </span>
                <span class="brand-name-print text-neutral-700">({item.brand_name_snapshot})</span>
                <span class="text-[10px] text-neutral-500">
                  {item.dosage_form_snapshot} &middot; {item.strength_snapshot}
                </span>
              </div>
              <p class="pl-4 pt-0.5 text-[12px] font-semibold text-neutral-900">
                {item.canonical_bengali_text || "#{item.dosage_matrix} — #{item.duration_expression}"}
              </p>
              <p :if={item.bengali_breakdown_text} class="pl-4 text-[10.5px] text-neutral-600">
                {item.bengali_breakdown_text}
              </p>
            </li>
          </ol>
          <p :if={@items == []} class="mt-2 text-[11px] italic text-neutral-400">
            No medications prescribed.
          </p>

          <div
            :if={String.trim(@general_advice || "") != ""}
            id="preview-advice-section"
            class="mt-auto pt-4"
          >
            <div class="border-t border-neutral-300 pt-2">
              <p class="text-[10px] font-semibold text-neutral-500">পরামর্শ / Advice</p>
              <p class="mt-0.5 whitespace-pre-line text-[11.5px] text-neutral-900">
                {@general_advice}
              </p>
            </div>
          </div>
        </div>
      </div>

      <!-- Signature + seal -->
      <footer class="mt-4 flex items-end justify-between gap-6 border-t border-neutral-900 pt-3">
        <div>
          <%= if @state == :locked && @qr_svg do %>
            <div class="flex items-end gap-2">
              <div
                id="prescription-qr-code"
                class="h-16 w-16 border border-neutral-900 p-0.5 [&>svg]:h-full [&>svg]:w-full"
              >
                {Phoenix.HTML.raw(@qr_svg)}
              </div>
              <p class="pb-0.5 text-[9px] leading-tight text-neutral-500">
                Tamper-Evident Ed25519 Seal<br />Scan to verify offline.
              </p>
            </div>
          <% else %>
            <div
              id="qr-seal-placeholder"
              class="flex h-14 w-20 items-center justify-center border border-dashed border-neutral-400 px-2 text-center font-mono text-[8.5px] leading-tight text-neutral-500"
            >
              Seal applied on finalization
            </div>
          <% end %>
        </div>
        <div class="text-right">
          <div class="w-44 border-t border-neutral-900 pt-1">
            <p class="text-[12px] font-semibold">{@doctor_name || "—"}</p>
            <p :if={@doctor_name && @bmdc_no} class="font-mono text-[10px] text-neutral-600">
              BM&amp;DC {@bmdc_no}
            </p>
            <p class="text-[9px] text-neutral-500">Signature</p>
          </div>
        </div>
      </footer>

      <div
        :if={@state == :locked && @qr_svg}
        id="print-verification-seal"
        class="hidden print:flex mt-2 items-center justify-between gap-4 border-t border-neutral-300 pt-2"
      >
        <div class="flex items-center gap-2">
          <div
            id="print-qr-seal-container"
            class="qr-seal-print h-12 w-12 bg-white [&>svg]:h-full [&>svg]:w-full"
          >
            {Phoenix.HTML.raw(@qr_svg)}
          </div>
          <div>
            <p class="text-[10px] font-bold text-neutral-900">
              Official Digital Verification Seal
            </p>
            <p :if={@doctor_name && @bmdc_no} class="font-mono text-[9px] text-neutral-600">
              BM&amp;DC: {@bmdc_no}
            </p>
            <p class="text-[9px] text-neutral-500">
              Digitally signed (Ed25519) &middot; High Court generics compliant
            </p>
          </div>
        </div>
        <p class="text-[9px] text-neutral-500">Page 1 of 1</p>
      </div>
    </section>
    """
  end
end
