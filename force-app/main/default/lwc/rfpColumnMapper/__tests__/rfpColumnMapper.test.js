import { createElement } from "lwc";
import RfpColumnMapper from "c/rfpColumnMapper";

const flush = () => Promise.resolve().then(() => Promise.resolve());

function mount(props) {
  const el = createElement("c-rfp-column-mapper", { is: RfpColumnMapper });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}

function change(el, selector, value) {
  el.shadowRoot
    .querySelector(selector)
    .dispatchEvent(new CustomEvent("change", { detail: { value } }));
}

describe("c-rfp-column-mapper", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("pre-fills from the mapping, lists missing required targets and enables Import when satisfied", async () => {
    const el = mount({
      headers: ["From", "To", "Qty"],
      sampleRows: [["Montreal", "Toronto", "2"]],
      mapping: { originCity: "From" }
    });
    expect(
      el.shadowRoot.querySelector('[data-target="originCity"]').value
    ).toBe("From");
    expect(
      el.shadowRoot.querySelector('[data-id="missing"]').textContent
    ).toContain("Destination city");
    expect(el.shadowRoot.querySelector('[data-id="import"]').disabled).toBe(
      true
    );
    const handler = jest.fn();
    el.addEventListener("mappingchange", handler);
    change(el, '[data-target="destinationCity"]', "To");
    await flush();
    expect(handler.mock.calls[0][0].detail.mapping.destinationCity).toBe("To");
    expect(el.shadowRoot.querySelector('[data-id="import"]').disabled).toBe(
      false
    );
    const imp = jest.fn();
    el.addEventListener("import", imp);
    el.shadowRoot.querySelector('[data-id="import"]').click();
    expect(imp.mock.calls[0][0].detail.mapping).toEqual({
      originCity: "From",
      destinationCity: "To"
    });
  });
});
