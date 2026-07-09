import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class Header extends NavigationMixin(LightningElement) {
    // Menu toggle functionality
    toggleMenu() {
        const menu = this.template.querySelector('.main-menu');
        menu.classList.toggle('active');
    }

    // Handle section clicks
    handleSectionClick(event) {
        event.preventDefault();
        const section = event.currentTarget.dataset.section;
        this.scrollToSection(section);
    }

    // Handle external link clicks
    handleExternalClick(event) {
        event.preventDefault();
        // Use NavigationMixin to navigate to external URLs
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: 'https://example.com'
            }
        });
    }

    // Scroll to section
    scrollToSection(sectionId) {
        const section = this.template.querySelector(`[data-section="${sectionId}"]`);
        if (section) {
            section.scrollIntoView({ behavior: 'smooth' });
        }
    }

    // Additional JavaScript functionality from your template
    // would be implemented as methods here
}