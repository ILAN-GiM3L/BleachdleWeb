// transition.js

// Function to handle AJAX page navigation
function loadPage(url) {
    // Smoothly fade out the current page content
    $('#content-container').fadeOut(300, function() {
        // Fetch the new page content via AJAX
        $.ajax({
            url: url,  // The URL to fetch the new page
            type: 'GET',
            success: function(response) {
                // Extract only the content we need from the new page
                var newContent = $(response).find('#content-container').html();
                
                // Replace the old content with the new content
                $('#content-container').html(newContent);
                
                // Re-initialize any JavaScript required for the new page (if needed)
                reinitializePage();

                // Smoothly fade in the new content
                $('#content-container').fadeIn(300);
            },
            error: function() {
                // In case of an error, just fade the content back in
                $('#content-container').fadeIn(300);
                alert('An error occurred while loading the page.');
            }
        });
    });
}

// Function to re-initialize page-specific content (e.g., event listeners, dynamic elements)
function reinitializePage() {
    // Initialize search input and other dynamic elements
    $('#search-bar').on('input', function() {
        // Example: live search handling logic (if applicable)
        let query = $(this).val().toLowerCase();
        // Your search logic goes here (e.g., filtering results)
        filterSearchResults(query);
    });

    // Re-initialize the Congratulations popup functionality
    $('#close-btn').on('click', function() {
        $('#congratulations-rectangle').fadeOut();
    });

    // Any other page-specific re-initialization can go here...
}

// Smooth scrolling for internal links within pages (optional)
$(document).on('click', 'a', function(e) {
    var href = $(this).attr('href');

    // Ignore non-HTML links (e.g., mailto:, etc.)
    if (href && href.charAt(0) !== '#' && href.indexOf('http') === -1) {
        e.preventDefault();  // Prevent the default link behavior
        
        loadPage(href);  // Load the page via AJAX
    }
});

// Optional: Reinitialize page elements when the document is ready
$(document).ready(function() {
    // Call the function to handle initial page load (if needed)
    reinitializePage();
});
