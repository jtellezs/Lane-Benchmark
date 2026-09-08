import { LightningElement, track } from 'lwc';

import getCarrierQuotes from '@salesforce/apex/PricingDepartmentController.getCarrierQuotes';
import getUniqueModeOptions from '@salesforce/apex/PricingDepartmentController.getUniqueModeOptions';

const COLUMNS = [
    { 
        label: '#', 
        fieldName: 'rowNumber', 
        type: 'number' 
    },

    { 
        label: 'Origin', 
        fieldName: 'Origin__c', 
        type: 'text' 
    },

    { 
        label: 'Destination', 
        fieldName: 'Destination__c', 
        type: 'text' 
    },

    { 
        label: 'Carrier Name', 
        fieldName: 'Carrier_Name__c', 
        type:'text'
    },

    { 
        label: 'Equipment', 
        fieldName: 'Equipment_Type__c', 
        type:'text',
    },

    { 
        label: 'Mode',
        fieldName: 'Mode__c',
        type: 'text'
    },

    { 
        label: 'Total (CAD)', 
        fieldName: 'CAD_Quote_Total__c',
        type:'currency'
    },

    { 
        label: 'Comments', 
        fieldName: 'Ops_Comments__c', 
        type:'text'
    },

    { 
        label: '# of pallets', 
        fieldName: 'Nb_Of_Pallets__c', 
        type:'text'
    },

    {
        label: 'Shippintg/Created Date',
        fieldName:'Quote_Date__c',
        type: 'text'
    },
    
    { 
        label: 'Quote ID', 
        fieldName: 'Name', 
        type: 'text'
    },

    {
        label: 'haz',
        fieldName: 'Hazmat__c',
        type: 'text'
    },

    {
        label: 'LD #',
        fieldName: 'rtms__Load__c',
        type: 'text'
    },
   
    
];


export default class PricingDepartment extends LightningElement {
    columns = COLUMNS;
    //Add the property to store the filters
    @track originFilter = '';
    @track destinationFilter = '';
    @track modeFilter = '';
    @track hazmatFilter = '';
    @track priceDepFilter = '';
    @track equipmentFilter = '';
    @track dateRangeFilter = '5'
    @track acceptedQuotesFilter= '';
    @track declinedQuotesFilter= '';
    @track modeOptions = [];
    @track expandedRowIndex = -1;
    @track additionalContentKey = '';
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
    @track titleValue='';
  //  @track minIndex;
   // @track maxIndex;

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


    handleHazmatFilterChange(event){
        this.isHazmatChecked = event.target.checked;
        console.log('isHazmatChecked:', this.isHazmatChecked);
        this.hazmatFilter = this.isHazmatChecked ? 'Hazmat' : '';
    }

    handlePriceDepFilterChange(event){
        this.isPriceDepChecked = event.target.checked;
        console.log('isPriceDepChecked:', this.isPriceDepChecked);
        this.priceDepFilter = this.isPriceDepChecked ? 'Market Test' : '';
    }


    handleEquipmentFilterChange(event){
        this.equipmentFilter = event.target.value;
    }

    handleDateRangeFilterChange(event){
        this.dateRangeFilter = event.target.value;

       
    }

    handleAcceptedQuotesFilterChange(event){
        this.isAcceptedQuotesChecked = event.target.checked;
        console.log('isAcceptedQuotesChecked:', isAcceptedQuotesChecked.isPriceDepChecked);
        this.acceptedQuotesFilter = this.isAcceptedQuotesChecked ? 'true' : '';
    }

    handleDeclinedQuotesFilterChange(event){
        this.isDeclinedQuotesChecked = event.target.checked;
        console.log('isDeclinedQuotesChecked:', this.isDeclinedQuotesChecked);
        this.declinedQuotesFilter = this.isDeclinedQuotesChecked ? 'true' : '';
    }
    handleCarrierClick(event) {
        const carrierId = event.currentTarget.dataset.id;
        this.selectedCarrier = this.carrierQuotesData.find(carrier => carrier.Id === carrierId);
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
    
    getAdditionalContentKey(carrierQuoteId) {
        return carrierQuoteId + '-additional-content';
    }
    

    applyFilters() {
        this.fetchCarrierQuotes();
    }
    
    get pageTitle() {
        return this.dateRangeFilter === '1' ? 'Stats for the last day' : `Stats for last ${this.dateRangeFilter} days`;
    }

    fetchModeOptions() {
        getUniqueModeOptions({ originFilter: this.originFilter, 
                                destinationFilter: this.destinationFilter })
            .then((data) => {
                this.modeOptions = data.map((mode) => {
                    return { label: mode, 
                            value: mode };
                });
                this.modeOptions.unshift({ label: '-- All --', value: '' });
                this.errors = undefined;
            })
            .catch((error) => {
                this.errors = error;
                this.modeOptions = undefined;
            });
    }
    

    async fetchCarrierQuotes() {
        this.isLoading = true; // Set isLoading to true before fetching data
        try{

             const result = await getCarrierQuotes({ originFilter: this.originFilter, 
                            destinationFilter: this.destinationFilter, 
                            modeFilter: this.modeFilter, 
                            hazmatFilter: this.hazmatFilter, 
                            equipmentFilter: this.equipmentFilter,
                            priceDepFilter: this.priceDepFilter,
                            dateRangeFilter: this.dateRangeFilter,
                            acceptedQuotesFilter: this.acceptedQuotesFilter,
                            declinedQuotesFilter : this.declinedQuotesFilter
                            })
                if (result) {
                    
                        this.carrierQuotesData = result.map((carrierQuote, index) => {
                            const rowNumber = index + 1;
                            const id = index;
                            let rowClass='';
                            let cellModeClass='';
                            let carrierNameClass='';
                            let priceClass='';
                            

                        switch (carrierQuote.Mode__c) {
                            case 'LTL':
                                //rowClass = 'ltl-row';
                                cellModeClass = 'ltl-cell';
                                break;
                            case 'Truckload':
                               // rowClass = 'ftl-row';
                                cellModeClass = 'ftl-cell';
                                break;
                            case 'Freight Forwarding':
                               // rowClass = 'freight-row';
                                cellModeClass = 'freight-cell';
                                break;
                            default:
                                break;
                        }

                    let additionalContentKey = carrierQuote.Id + '-additional-content';

                    const showAdditionalContent = this.additionalContentKey === carrierQuote.Id + '-additional-content';
                    return { ...carrierQuote, 
                                rowNumber, 
                                //rowClass, 
                                cellModeClass,   
                                id,
                                showAdditionalContent,
                                additionalContentKey,
                            };
                        });
                        
                        this.errors = undefined;
                        this.calculateStats(result);
                        this.generateModeOptions(result);
                    
                }else {
                    this.errors = 'No data found';
                    this.carrierQuotesData = undefined;
                }
                
        }catch (error)  {
            this.errors = error;
            this.carrierQuotesData = undefined;
        } finally {
            this.isLoading = false;
        }
    }
    
    generateModeOptions(carrierQuotes) {
        const modeSet = new Set();
    
        carrierQuotes.forEach((carrierQuote) => {
            modeSet.add(carrierQuote.Mode__c);
        });
    
        this.modeOptions = Array.from(modeSet).map(mode => ({ label: mode, value: mode }));
        //add the All option to thew top of thw list
        this.modeOptions.unshift({ label: '-- All --', value: '' });
    }
    
    calculateStats(carrierQuotes) {
        let sum = 0;
        let count = 0;
        let countZero = 0;
        let min = Number.MAX_VALUE;
        let max = Number.MIN_VALUE;
       let minRowNumber = 0;
       let maxRowNumber = 0;
    
        carrierQuotes.forEach((carrierQuote) => {
            const quoteTotal = carrierQuote.CAD_Quote_Total__c;
    
            // Ignore zero values
            if (quoteTotal === 0) {
                countZero++
                return;
            }
    
            if (quoteTotal < min) {
                min = quoteTotal;
               // minRowNumber = index +1;
            }
    
            if (quoteTotal > max) {
                max = quoteTotal;
               // maxRowNumber = index +1;
            }
    
            sum += quoteTotal;
            count++;
        });
    
        this.minQuoteTotal = min === Number.MAX_VALUE ? 0 : min;
        this.maxQuoteTotal = max === Number.MIN_VALUE ? 0 : max;
        this.avgQuoteTotal = count === 0 ? 0 : sum / count;
        this.roundedAVG=this.avgQuoteTotal.toFixed(2);
        this.nbOfQuotes = count + countZero;
        this.nbOfQuotesNotZero = count;
       this.maxIndex = maxRowNumber;
       this.minIndex = minRowNumber;
    }

    getRowClass(row) {
    return row.Mode__c === 'LTL' ? 'ltl-row' : '';
    }

    resetFilters() {
        this.originFilter = '';
        this.destinationFilter = '';
        this.modeFilter = '';
        this.equipmentFilter = '';
        this.dateRangeFilter = '5';

        // Reset the checkbox properties
        this.isHazmatChecked = false;
        this.hazmatFilter = '';

        this.isPriceDepChecked = false;
        this.priceDepFilter = '';

        this.isAcceptedQuotesChecked = false;
        this.acceptedQuotesFilter = '';

        this.isDeclinedQuotesChecked = false;
        this.declinedQuotesFilter = '';

        this.fetchCarrierQuotes();
    }
  
}