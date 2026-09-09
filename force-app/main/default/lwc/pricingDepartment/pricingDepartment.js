import { LightningElement, track } from "lwc";

import getCarrierQuotes from "@salesforce/apex/PricingDepartmentController.getCarrierQuotes";
import { calculateStats, shapeRows, modeOptionsFrom } from "c/quoteStats";

const COLUMNS = [
  {
    label: "#",
    fieldName: "rowNumber",
    type: "number"
  },

  {
    label: "Origin",
    fieldName: "Origin__c",
    type: "text"
  },

  {
    label: "Destination",
    fieldName: "Destination__c",
    type: "text"
  },

  {
    label: "Carrier Name",
    fieldName: "Carrier_Name__c",
    type: "text"
  },

  {
    label: "Equipment",
    fieldName: "Equipment_Type__c",
    type: "text"
  },

  {
    label: "Mode",
    fieldName: "Mode__c",
    type: "text"
  },

  {
    label: "Total (CAD)",
    fieldName: "CAD_Quote_Total__c",
    type: "currency"
  },

  {
    label: "Comments",
    fieldName: "Ops_Comments__c",
    type: "text"
  },

  {
    label: "# of pallets",
    fieldName: "Nb_Of_Pallets__c",
    type: "text"
  },

  {
    label: "Shippintg/Created Date",
    fieldName: "Quote_Date__c",
    type: "text"
  },

  {
    label: "Quote ID",
    fieldName: "Name",
    type: "text"
  },

  {
    label: "haz",
    fieldName: "Hazmat__c",
    type: "text"
  },

  {
    label: "LD #",
    fieldName: "rtms__Load__c",
    type: "text"
  }
];

export default class PricingDepartment extends LightningElement {
  columns = COLUMNS;
  //Add the property to store the filters
  @track originFilter = "";
  @track destinationFilter = "";
  @track modeFilter = "";
  @track hazmatFilter = "";
  @track priceDepFilter = "";
  @track equipmentFilter = "";
  @track dateRangeFilter = "5";
  @track acceptedQuotesFilter = "";
  @track declinedQuotesFilter = "";
  @track modeOptions = [];
  @track isDialogOpen = false;
  @track selectedCarrier = {};
  @track carrierQuotesData;
  @track errors;
  @track isLoading = true;
  // Add properties to track the checked state of checkboxes
  @track isHazmatChecked = false;
  @track isPriceDepChecked = false;
  @track isAcceptedQuotesChecked = false;
  @track isDeclinedQuotesChecked = false;
  // Add the properties to store the calculated values
  @track minQuoteTotal;
  @track maxQuoteTotal;
  @track avgQuoteTotal;
  @track roundedAVG;
  @track nbOfQuotes;
  @track nbOfQuotesNotZero;

  connectedCallback() {
    this.fetchCarrierQuotes();
  }

  handleOriginFilterChange(event) {
    this.originFilter = event.target.value;
  }

  handleDestinationFilterChange(event) {
    this.destinationFilter = event.target.value;
  }

  handleModeFilterChange(event) {
    this.modeFilter = event.target.value;
  }

  handleHazmatFilterChange(event) {
    this.isHazmatChecked = event.target.checked;
    this.hazmatFilter = this.isHazmatChecked ? "Hazmat" : "";
  }

  handlePriceDepFilterChange(event) {
    this.isPriceDepChecked = event.target.checked;
    this.priceDepFilter = this.isPriceDepChecked ? "Market Test" : "";
  }

  handleEquipmentFilterChange(event) {
    this.equipmentFilter = event.target.value;
  }

  handleDateRangeFilterChange(event) {
    this.dateRangeFilter = event.target.value;
  }

  handleAcceptedQuotesFilterChange(event) {
    this.isAcceptedQuotesChecked = event.target.checked;
    this.acceptedQuotesFilter = this.isAcceptedQuotesChecked ? "true" : "";
  }

  handleDeclinedQuotesFilterChange(event) {
    this.isDeclinedQuotesChecked = event.target.checked;
    this.declinedQuotesFilter = this.isDeclinedQuotesChecked ? "true" : "";
  }
  handleCarrierClick(event) {
    const carrierId = event.currentTarget.dataset.id;
    this.selectedCarrier = this.carrierQuotesData.find(
      (carrier) => carrier.Id === carrierId
    );
    this.isDialogOpen = true;
  }

  closeDialog() {
    this.isDialogOpen = false;
  }

  handleRowClick(event) {
    const rowIndex = event.currentTarget.dataset.index;
    const carrierQuote = this.carrierQuotesData[rowIndex];
    // Toggle the showAdditionalContent property
    carrierQuote.showAdditionalContent = !carrierQuote.showAdditionalContent;
    // Update the carrierQuotesData array to trigger a re-render
    this.carrierQuotesData = [...this.carrierQuotesData];
  }

  applyFilters() {
    this.fetchCarrierQuotes();
  }

  get pageTitle() {
    return this.dateRangeFilter === "1"
      ? "Stats for the last day"
      : `Stats for last ${this.dateRangeFilter} days`;
  }

  async fetchCarrierQuotes() {
    this.isLoading = true; // Set isLoading to true before fetching data
    try {
      const result = await getCarrierQuotes({
        originFilter: this.originFilter,
        destinationFilter: this.destinationFilter,
        modeFilter: this.modeFilter,
        hazmatFilter: this.hazmatFilter,
        equipmentFilter: this.equipmentFilter,
        priceDepFilter: this.priceDepFilter,
        dateRangeFilter: this.dateRangeFilter,
        acceptedQuotesFilter: this.acceptedQuotesFilter,
        declinedQuotesFilter: this.declinedQuotesFilter
      });
      if (result) {
        this.carrierQuotesData = shapeRows(result);
        this.errors = undefined;
        this.applyStats(calculateStats(result));
        this.modeOptions = modeOptionsFrom(result);
      } else {
        this.errors = "No data found";
        this.carrierQuotesData = undefined;
      }
    } catch (error) {
      this.errors = error;
      this.carrierQuotesData = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  applyStats(stats) {
    this.minQuoteTotal = stats.min;
    this.maxQuoteTotal = stats.max;
    this.avgQuoteTotal = stats.avg;
    this.roundedAVG = stats.roundedAvg;
    this.nbOfQuotes = stats.nbOfQuotes;
    this.nbOfQuotesNotZero = stats.nbOfQuotesNotZero;
  }

  resetFilters() {
    this.originFilter = "";
    this.destinationFilter = "";
    this.modeFilter = "";
    this.equipmentFilter = "";
    this.dateRangeFilter = "5";

    // Reset the checkbox properties
    this.isHazmatChecked = false;
    this.hazmatFilter = "";

    this.isPriceDepChecked = false;
    this.priceDepFilter = "";

    this.isAcceptedQuotesChecked = false;
    this.acceptedQuotesFilter = "";

    this.isDeclinedQuotesChecked = false;
    this.declinedQuotesFilter = "";

    this.fetchCarrierQuotes();
  }
}
