#include "httpd.h"
#include "http_config.h"
#include "http_core.h"
#include "http_log.h"
#include "http_main.h"
#include "http_protocol.h"

#include "libtmcd.h"

module MODULE_VAR_EXPORT tmcd_module;

static int handle_request(request_rec *r)
{
	tmcdreq_t tmcdreq, *reqp = &tmcdreq;
	tmcdresp_t *response = NULL;
	char *command;
	struct in_addr myaddr;
	struct in_addr client_addr;
	int err;
	int status;
	int rc = OK;

	reqp->istcp = 1;
	reqp->isssl = 1; /* FIXME */

	if (strcmp(r->handler, "tmcd")) {
		rc = DECLINED;
		goto err;
	}

#if 0
	r->allowed |= (AP_METHOD_BIT << M_GET);
	if (r->method_number != M_GET) {
		rc = DECLINED;
		goto err;
	}
#endif

	memset(reqp, 0, sizeof(*reqp));

	reqp->version = 1; /* FIXME */

	/* FIXME eliminate or fix myaddr */

	tmcd_init(reqp, &myaddr, NULL);

	/* FIXME do real argument parsing here */
	if (r->args) {
		command = r->args;
	}

	client_addr = r->connection->remote_addr.sin_addr;

	/* FIXME handle wanodekey */
	if ((err = iptonodeid(reqp, client_addr, NULL))) {
#if 0
		if (reqp->isvnode) {
			error("No such vnode %s associated with %s\n",
			      reqp->vnodeid, inet_ntoa(client->sin_addr));
		}
		else {
			error("No such node: %s\n",
			      inet_ntoa(client->sin_addr));
		}
#endif
		rc = HTTP_BAD_REQUEST;
		goto err;
	}

	/* FIXME */
	status = tmcd_handle_request(reqp, &response, command, NULL);

	if (status == TMCD_STATUS_OK) {
		r->content_type = response->type;
		ap_set_content_length(r, response->length);
		/* FIXME doctype */
		ap_soft_timeout("tmcd response call trace", r);
		ap_send_http_header(r);
		ap_rprintf(r, "%s", response->data);
		ap_kill_timeout(r);
		goto done;
	}
	else {
		rc = HTTP_BAD_REQUEST;
		goto err;
	}
err:
done:
	if (response)
		tmcd_free_response(response);

	return rc;
}

static const handler_rec tmcd_handlers[] =
{
	{"tmcd", handle_request},
	{NULL}
};

module MODULE_VAR_EXPORT tmcd_module = {
	STANDARD_MODULE_STUFF,
	NULL,               /* module initializer */
	NULL,  /* per-directory config creator */
	NULL,   /* dir config merger */
	NULL,       /* server config creator */
	NULL,        /* server config merger */
	NULL,               /* command table */
	tmcd_handlers,           /* [9] list of handlers */
	NULL,  /* [2] filename-to-URI translation */
	NULL,      /* [5] check/validate user_id */
	NULL,       /* [6] check user_id is valid *here* */
	NULL,     /* [4] check access by host address */
	NULL,       /* [7] MIME type checker/setter */
	NULL,        /* [8] fixups */
	NULL,             /* [10] logger */
#if MODULE_MAGIC_NUMBER >= 19970103
	NULL,      /* [3] header parser */
#endif
#if MODULE_MAGIC_NUMBER >= 19970719
	NULL,         /* process initializer */
#endif
#if MODULE_MAGIC_NUMBER >= 19970728
	NULL,         /* process exit/cleanup */
#endif
#if MODULE_MAGIC_NUMBER >= 19970902
	NULL  /* [1] post read_request handling */
#endif
};
