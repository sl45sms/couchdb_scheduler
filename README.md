couchdb_scheduler
=================
***!!!WARNING!!! ugly code lives here!***  
This is a work in progress(not even alpha)...


Yes [CouchDB](http://couchdb.apache.org/) it is database and databases normaly don't do anything except data manipulation, reading, search, writing rows etc.   
But CouchDB is a lot more, it is a web server (Mochiweb) that can host applications writed with javascript and html.

One of the things may missing when write applications is the abiliti to perform server side task at specific time.

One solution is to put external scheduler that operates as a client, but since you are already running a great server why not take advantage?  

Here comes couchdb_scheduler, you can schedule a javascript function on your design document to execute at any time.  

Examples
--------
For example you have a customer and you need every month for the next 10 months to update invoice with charges.

`curl -X POST http://127.0.0.1:5984/dbname/_design/webapp/_schedules/updateinvoicefun/R10%2FPT1M/customer_invoice_doc_id?charge=100`

as you can imagine from the above url the module register a new type (_schedule) of design handler, there is defined the function "updateinvoicefun" that do the job.

```
{
   "_id": "_design/webapp",
   "_rev": "1-a3b0d2074c7d571efdc1a50112a54480",
   "rewrites": [

   ],
...
   "schedules": {
       "updateinvoicefun": "function(doc,req){
       if (!doc.Amount) doc.Amount = 100; doc.Amount += req.amount;
       var message = 'charge it!';
       return [doc, message];}"
   },
 ...
   "updates": {
   }
}

```


functions for schedules works the same as regular [update functions](http://couchapp.org/page/update-functions).


more examples:  

Schedule to run myfun one hour from now  
`curl -X POST http://127.0.0.1:5984/dbname/_design/webapp/_schedules/myfunc/PT1H/doc_id`

Schedule to run myfun at 2100-1-1T0:0:0 !  
`curl -X POST http://127.0.0.1:5984/dbname/_design/webapp/_schedules/myfunc/2100/doc_id`


time date and repeats specified using [iso8601](http://en.wikipedia.org/wiki/ISO_8601) syndax


*English isn’t my first language, so please excuse any mistakes, typo corrections is more than welcome.*



