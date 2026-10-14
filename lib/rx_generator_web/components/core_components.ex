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
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
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
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
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
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
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

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
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
    <div class="relative w-full max-w-3xl mx-auto my-6">
      <form id="omnibar-form" phx-submit="commit_omnibar" class="relative">
        <div class={[
          "flex items-center rounded-xl bg-white shadow-lg border px-4 py-3 transition-all",
          @error && "border-amber-500 ring-2 ring-amber-200",
          !@error &&
            "border-zinc-300 focus-within:border-zinc-800 focus-within:ring-2 focus-within:ring-zinc-400"
        ]}>
          <.icon name="hero-magnifying-glass" class="w-6 h-6 text-zinc-400 mr-3" />
          <input
            id={@id}
            name="query"
            type="text"
            value={@query}
            autofocus
            autocomplete="off"
            placeholder="Type shorthand (e.g. napa xtra 1+0+1 5d pc)..."
            phx-keyup="parse_and_suggest"
            phx-debounce="50"
            phx-hook="Omnibar"
            class="w-full bg-transparent border-0 p-0 text-zinc-900 placeholder:text-zinc-400 text-lg font-medium focus:outline-none focus:ring-0"
          />
          <kbd class="hidden sm:inline-block px-2 py-1 text-xs font-semibold text-zinc-500 bg-zinc-100 border border-zinc-200 rounded-md">
            Enter ↵
          </kbd>
        </div>
      </form>

      <%= if @candidates != [] do %>
        <div
          id="omnibar-dropdown"
          class="absolute left-0 right-0 mt-2 z-50 bg-white rounded-xl shadow-2xl border border-zinc-200 overflow-hidden divide-y divide-zinc-100 animate-in fade-in duration-100"
        >
          <div
            :for={{candidate, idx} <- Enum.with_index(@candidates)}
            id={"candidate-#{idx}"}
            class={[
              "px-4 py-2.5 flex items-center justify-between cursor-pointer transition-colors",
              idx == @highlighted_index && "bg-zinc-100 font-medium text-zinc-900",
              idx != @highlighted_index && "hover:bg-zinc-50 text-zinc-700"
            ]}
          >
            <div>
              <span class="font-bold text-zinc-900">{candidate.brand_name}</span>
              <span class="text-xs text-zinc-500 ml-2">({candidate.generic_name})</span>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-xs font-medium bg-zinc-100 text-zinc-600 px-2 py-0.5 rounded-full border border-zinc-200">
                {candidate.dosage_form} &bull; {candidate.strength}
              </span>
              <%= if idx == @highlighted_index do %>
                <span class="text-[10px] font-bold text-zinc-400 uppercase tracking-widest hidden sm:inline">
                  Tab ⇥
                </span>
              <% end %>
            </div>
          </div>

          <div class="px-4 py-1.5 bg-zinc-50 text-[11px] text-zinc-400 flex items-center justify-between">
            <span>↑↓ to navigate &bull; Tab to complete &bull; Esc to dismiss</span>
            <span>Local DGDA Snapshot</span>
          </div>
        </div>
      <% end %>

      <%= if @error do %>
        <div class="mt-2 text-sm text-amber-600 font-medium flex items-center gap-1.5">
          <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-amber-600" />
          {@error}
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the prescription canvas displaying medication items.
  """
  attr :id, :string, default: "prescription-canvas"
  attr :items, :list, default: []
  attr :state, :atom, default: :draft
  attr :rx_number, :string, default: nil

  def prescription_canvas(assigns) do
    ~H"""
    <div
      id={@id}
      class="w-full max-w-3xl mx-auto bg-white rounded-2xl shadow-xl border border-zinc-200 p-8 min-h-100"
    >
      <div class="border-b border-zinc-200 pb-4 mb-6 flex justify-between items-center">
        <div>
          <div class="flex items-center gap-3">
            <h2 class="text-2xl font-black text-zinc-900 tracking-tight">PRESCRIPTION (Rx)</h2>
            <%= if @state == :locked do %>
              <span
                id="prescription-locked-badge"
                class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-black uppercase tracking-wider bg-rose-100 text-rose-800 border border-rose-300"
              >
                <.icon name="hero-lock-closed" class="w-3.5 h-3.5" /> FINALIZED & IMMUTABLE
              </span>
            <% else %>
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold uppercase tracking-wider bg-amber-100 text-amber-800 border border-amber-300">
                DRAFT
              </span>
            <% end %>
          </div>
          <p class="text-xs font-semibold text-zinc-500 uppercase tracking-widest mt-0.5">
            Clinical Order Record {if @rx_number, do: "• #{@rx_number}"}
          </p>
        </div>
        <div class="text-right text-xs text-zinc-400">
          Edge-Native Air-Gapped Engine
        </div>
      </div>

      <div class="space-y-4">
        <%= if @items == [] do %>
          <div class="text-center py-16 text-zinc-400 border-2 border-dashed border-zinc-200 rounded-xl">
            <.icon name="hero-document-text" class="w-10 h-10 mx-auto mb-2 text-zinc-300" />
            <p class="text-sm font-medium">No medications added yet.</p>
            <p class="text-xs mt-1">
              Use the omnibar above to enter medications via keyboard shorthand.
            </p>
          </div>
        <% else %>
          <div
            :for={{item, index} <- Enum.with_index(@items)}
            id={"rx-item-#{index}"}
            class="p-4 rounded-xl border border-zinc-100 bg-zinc-50/50 hover:bg-zinc-50 transition-colors"
          >
            <div class="flex items-baseline justify-between">
              <div>
                <span class="text-xs font-bold text-zinc-400 mr-2">{index + 1}.</span>
                <span class="text-lg font-black uppercase tracking-wide text-zinc-900">
                  {String.upcase(item.generic_name_snapshot)}
                </span>
                <span class="ml-2 text-sm font-semibold text-zinc-600">
                  ({item.brand_name_snapshot})
                </span>
              </div>
              <span class="text-xs font-medium text-zinc-500 bg-zinc-200/70 px-2.5 py-0.5 rounded-full">
                {item.dosage_form_snapshot} &bull; {item.strength_snapshot}
              </span>
            </div>

            <div class="mt-3 flex flex-wrap items-baseline gap-3">
              <%= if item.canonical_bengali_text do %>
                <span class="text-base font-bold text-emerald-800 tracking-wide">
                  {item.canonical_bengali_text}
                </span>
              <% else %>
                <span class="bg-emerald-50 border border-emerald-200 px-2.5 py-1 rounded-md text-sm font-semibold text-emerald-800">
                  {item.dosage_matrix}
                </span>
                <span class="text-zinc-400">&bull;</span>
                <span class="text-sm font-semibold text-emerald-800">{item.duration_expression}</span>
                <%= if item.timing_instruction do %>
                  <span class="text-zinc-400">&bull;</span>
                  <span class="text-zinc-600 font-medium text-sm">({item.timing_instruction})</span>
                <% end %>
              <% end %>

              <%= if item.bengali_breakdown_text do %>
                <span class="text-xs font-medium text-zinc-500 bg-zinc-100 px-2 py-0.5 rounded">
                  {item.bengali_breakdown_text}
                </span>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <div class="mt-8 pt-6 border-t border-zinc-200 flex justify-between items-center print:hidden">
        <div>
          <%= if @state == :locked do %>
            <p class="text-xs text-zinc-500">
              Prescription finalized. Modifications and deletions are permanently prohibited.
            </p>
          <% else %>
            <p class="text-xs text-zinc-500">
              Review medications carefully before sealing prescription.
            </p>
          <% end %>
        </div>
        <div>
          <%= if @state != :locked do %>
            <button
              id="finalize-prescription-btn"
              type="button"
              phx-click="finalize_prescription"
              disabled={@items == []}
              class={[
                "inline-flex items-center gap-2 px-5 py-2.5 rounded-xl font-bold text-sm shadow-sm transition-all",
                if(@items == [],
                  do: "bg-zinc-200 text-zinc-400 cursor-not-allowed",
                  else: "bg-zinc-900 text-white hover:bg-zinc-800 active:scale-95 cursor-pointer"
                )
              ]}
            >
              <.icon name="hero-lock-closed" class="w-4 h-4" /> Finalize Prescription
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
